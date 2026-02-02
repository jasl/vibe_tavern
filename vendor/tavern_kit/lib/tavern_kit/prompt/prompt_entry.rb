# frozen_string_literal: true

require_relative "../text/pattern_matcher"

module TavernKit
  module Prompt
    # Models a single Prompt Manager "Prompt Entry".
    #
    # - Pinned prompts: built-in placeholders that map to internal
    #   block groups (main prompt, persona, character defs, etc.)
    # - Custom prompts: user-defined text injected either relatively (drag&drop)
    #   or inside chat history (in-chat prompts)
    class PromptEntry
      POSITIONS = %i[relative in_chat].freeze
      ROLES = %i[system user assistant].freeze

      attr_reader :id, :name, :enabled, :pinned, :role, :position, :depth, :order, :content, :triggers, :forbid_overrides, :conditions

      def initialize(
        id:,
        name: nil,
        enabled: true,
        pinned: false,
        role: :system,
        position: :relative,
        depth: 4,
        order: 100,
        content: nil,
        triggers: [],
        forbid_overrides: false,
        conditions: nil
      )
        @id = id.to_s
        @name = (name || @id).to_s
        @enabled = !!enabled
        @pinned = !!pinned
        @role = role.respond_to?(:to_sym) ? role.to_sym : :system
        @position = position.respond_to?(:to_sym) ? position.to_sym : :relative
        @depth = depth.to_i.abs
        @order = order.to_i
        @content = content&.to_s
        @triggers = Array(triggers).map { |t| Coerce.generation_type(t) }.compact.uniq.freeze
        @forbid_overrides = !!forbid_overrides
        @conditions = conditions
      end

      def enabled? = @enabled
      def pinned? = @pinned
      def in_chat? = @position == :in_chat
      def relative? = @position == :relative

      # Check if this entry should activate for the given generation type.
      def triggered_by?(generation_type)
        return true if @triggers.empty?
        @triggers.include?(Coerce.generation_type(generation_type))
      end

      # Evaluate this prompt entry's conditional activation rules (if any).
      def active_for?(context)
        return true if @conditions.nil? || @conditions.empty?
        return false unless context.is_a?(Hash)
        evaluate_conditions(@conditions, context)
      end

      def to_h
        {
          id: id, name: name, enabled: enabled, pinned: pinned, role: role,
          position: position, depth: depth, order: order, content: content,
          triggers: triggers, forbid_overrides: forbid_overrides, conditions: conditions,
        }
      end

      def self.from_hash(hash)
        h = Utils::HashAccessor.wrap(hash)

        id = h.fetch(:id, :key)
        return nil unless id

        new(
          id: id,
          name: h[:name],
          enabled: h.bool(:enabled, default: true),
          pinned: h.bool(:pinned, default: false),
          role: Coerce.role(h[:role], default: :system),
          position: h[:position].to_s.strip.downcase == "in_chat" ? :in_chat : :relative,
          depth: h.int(:depth, default: 4),
          order: h.int(:order, default: 100),
          content: h[:content],
          triggers: Coerce.triggers(h.fetch(:triggers, :injection_trigger) || []),
          forbid_overrides: h.bool(:forbid_overrides, default: false),
          conditions: h[:conditions] ? Utils.deep_symbolize_keys(h[:conditions]) : nil,
        )
      end

      private

      def evaluate_conditions(cond_hash, context)
        return true if cond_hash.nil? || cond_hash.empty?
        return false unless cond_hash.is_a?(Hash)

        if cond_hash.key?(:all)
          return false unless Array(cond_hash[:all]).all? { |c| evaluate_conditions(c, context) }
        end

        if cond_hash.key?(:any)
          return false unless Array(cond_hash[:any]).any? { |c| evaluate_conditions(c, context) }
        end

        return false if cond_hash.key?(:chat) && !chat_conditions_pass?(cond_hash[:chat], context)
        return false if cond_hash.key?(:turns) && !turns_conditions_pass?(cond_hash[:turns], context)
        return false if cond_hash.key?(:character) && !character_conditions_pass?(cond_hash[:character], context)
        return false if cond_hash.key?(:user) && !user_conditions_pass?(cond_hash[:user], context)

        true
      end

      def chat_conditions_pass?(chat_cond, context)
        chat_messages = Array(context[:chat_scan_messages]).map(&:to_s)
        default_depth = context[:default_chat_depth]&.to_i || 2

        cfg = case chat_cond
        when String then { any: [chat_cond] }
        when Array then { any: chat_cond }
        when Hash then Utils.deep_symbolize_keys(chat_cond)
        else return true
        end

        depth = (cfg[:depth] || default_depth).to_i.clamp(0, 100)
        return false if depth <= 0

        scan_text = chat_messages.first(depth).join("\n")
        case_sensitive = Coerce.bool(cfg[:case_sensitive], default: false)
        match_whole_words = Coerce.bool(cfg[:match_whole_words], default: false)

        any_patterns = cfg[:any]
        all_patterns = cfg[:all]

        return true if Array(any_patterns).empty? && Array(all_patterns).empty?

        if any_patterns
          return false unless Array(any_patterns).any? { |p| pattern_matches?(p, scan_text, case_sensitive:, match_whole_words:) }
        end

        if all_patterns
          return false unless Array(all_patterns).all? { |p| pattern_matches?(p, scan_text, case_sensitive:, match_whole_words:) }
        end

        true
      end

      def turns_conditions_pass?(turns_cond, context)
        turn = context[:turn_count].to_i

        cfg = case turns_cond
        when Integer then { equals: turns_cond }
        when String then turns_cond.match?(/\A-?\d+\z/) ? { equals: turns_cond.to_i } : {}
        when Hash then Utils.deep_symbolize_keys(turns_cond)
        else {}
        end

        return false if cfg[:min] && turn < cfg[:min].to_i
        return false if cfg[:max] && turn > cfg[:max].to_i
        return false if cfg[:equals] && turn != cfg[:equals].to_i
        return false if cfg[:every] && (cfg[:every].to_i <= 0 || (turn % cfg[:every].to_i) != 0)

        true
      end

      def character_conditions_pass?(char_cond, context)
        character = context[:character]
        return false unless character

        cfg = case char_cond
        when String then { name: char_cond }
        when Hash then Utils.deep_symbolize_keys(char_cond)
        else {}
        end

        data = character.respond_to?(:data) ? character.data : character

        return false if cfg[:name] && !attribute_matches?(cfg[:name], data_attr(data, :name))
        return false if cfg[:creator] && !attribute_matches?(cfg[:creator], data_attr(data, :creator))
        return false if cfg[:character_version] && !attribute_matches?(cfg[:character_version], data_attr(data, :character_version))

        tags = data.respond_to?(:tags) ? Array(data.tags).map(&:to_s) : []

        if cfg[:tags_any]
          wanted = Array(cfg[:tags_any]).map(&:to_s)
          return false unless wanted.any? { |t| tags.any? { |tag| tag.casecmp?(t) } }
        end

        if cfg[:tags_all]
          wanted = Array(cfg[:tags_all]).map(&:to_s)
          return false unless wanted.all? { |t| tags.any? { |tag| tag.casecmp?(t) } }
        end

        true
      end

      def user_conditions_pass?(user_cond, context)
        user = context[:user]
        return false unless user

        cfg = case user_cond
        when String then { name: user_cond }
        when Hash then Utils.deep_symbolize_keys(user_cond)
        else {}
        end

        return false if cfg[:name] && !attribute_matches?(cfg[:name], data_attr(user, :name))
        if cfg[:persona]
          persona_text = user.respond_to?(:persona_text) ? user.persona_text.to_s : ""
          return false unless pattern_matches?(cfg[:persona], persona_text, case_sensitive: false, match_whole_words: false)
        end

        true
      end

      def data_attr(obj, attr)
        obj.respond_to?(attr) ? obj.send(attr).to_s : ""
      end

      def attribute_matches?(pattern, value)
        value.to_s.strip.casecmp?(pattern.to_s.strip)
      end

      def pattern_matches?(pattern, text, case_sensitive:, match_whole_words:)
        Text::PatternMatcher.match?(
          pattern,
          text,
          case_sensitive: case_sensitive,
          match_whole_words: match_whole_words,
        )
      end
    end
  end
end
