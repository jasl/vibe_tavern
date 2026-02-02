# frozen_string_literal: true

module TavernKit
  module Lore
    # A single lorebook entry.
    #
    # This structure matches CCv2/CCv3 "character_book.entries" fields, while
    # allowing platform-specific fields to live under `extensions`.
    Entry = Data.define(
      :keys,
      :content,
      :extensions,
      :enabled,
      :insertion_order,
      :use_regex,
      :case_sensitive,
      :constant,
      :name,
      :priority,
      :id,
      :comment,
      :selective,
      :secondary_keys,
      :position,
    ) do
      def initialize(
        keys:,
        content:,
        extensions: nil,
        enabled: true,
        insertion_order: 100,
        use_regex: false,
        case_sensitive: nil,
        constant: nil,
        name: nil,
        priority: nil,
        id: nil,
        comment: nil,
        selective: nil,
        secondary_keys: nil,
        position: nil
      )
        keys = Array(keys).map(&:to_s)
        raise ArgumentError, "keys must be a non-empty Array<String>" if keys.empty?

        content = content.to_s

        if !extensions.nil? && !extensions.is_a?(Hash)
          raise ArgumentError, "extensions must be a Hash (or nil), got: #{extensions.class}"
        end
        extensions = (extensions || {}).transform_keys(&:to_s).dup.freeze

        unless enabled == true || enabled == false
          raise ArgumentError, "enabled must be a Boolean, got: #{enabled.class}"
        end

        unless insertion_order.is_a?(Integer)
          raise ArgumentError, "insertion_order must be an Integer, got: #{insertion_order.class}"
        end

        unless use_regex == true || use_regex == false
          raise ArgumentError, "use_regex must be a Boolean, got: #{use_regex.class}"
        end

        if !case_sensitive.nil? && case_sensitive != true && case_sensitive != false
          raise ArgumentError, "case_sensitive must be a Boolean (or nil), got: #{case_sensitive.class}"
        end

        if !constant.nil? && constant != true && constant != false
          raise ArgumentError, "constant must be a Boolean (or nil), got: #{constant.class}"
        end

        if !name.nil? && !name.is_a?(String)
          raise ArgumentError, "name must be a String (or nil), got: #{name.class}"
        end

        if !priority.nil? && !priority.is_a?(Integer)
          raise ArgumentError, "priority must be an Integer (or nil), got: #{priority.class}"
        end

        if !id.nil? && !id.is_a?(String)
          raise ArgumentError, "id must be a String (or nil), got: #{id.class}"
        end

        if !comment.nil? && !comment.is_a?(String)
          raise ArgumentError, "comment must be a String (or nil), got: #{comment.class}"
        end

        if !selective.nil? && selective != true && selective != false
          raise ArgumentError, "selective must be a Boolean (or nil), got: #{selective.class}"
        end

        if !secondary_keys.nil?
          unless secondary_keys.is_a?(Array) && secondary_keys.all? { |k| k.is_a?(String) }
            raise ArgumentError, "secondary_keys must be an Array<String> (or nil)"
          end
        end

        if !position.nil? && !position.is_a?(String)
          raise ArgumentError, "position must be a String (or nil), got: #{position.class}"
        end

        super(
          keys: keys.freeze,
          content: content,
          extensions: extensions,
          enabled: enabled,
          insertion_order: insertion_order,
          use_regex: use_regex,
          case_sensitive: case_sensitive,
          constant: constant,
          name: name,
          priority: priority,
          id: id,
          comment: comment,
          selective: selective,
          secondary_keys: secondary_keys,
          position: position,
        )
      end

      def enabled? = enabled == true
      def regex? = use_regex == true
      def constant? = constant == true

      def selective?
        selective == true && secondary_keys.is_a?(Array) && secondary_keys.any?
      end

      def to_h
        h = {
          "keys" => keys,
          "content" => content,
          "enabled" => enabled,
          "insertion_order" => insertion_order,
          "use_regex" => use_regex,
          "extensions" => extensions,
        }
        h["case_sensitive"] = case_sensitive unless case_sensitive.nil?
        h["constant"] = constant unless constant.nil?
        h["name"] = name unless name.nil?
        h["priority"] = priority unless priority.nil?
        h["id"] = id unless id.nil?
        h["comment"] = comment unless comment.nil?
        h["selective"] = selective unless selective.nil?
        h["secondary_keys"] = secondary_keys unless secondary_keys.nil?
        h["position"] = position unless position.nil?
        h
      end

      def self.from_h(hash)
        raise ArgumentError, "Entry must be a Hash" unless hash.is_a?(Hash)

        h = hash.transform_keys(&:to_s)
        new(
          keys: h.fetch("keys"),
          content: h.fetch("content"),
          extensions: h["extensions"],
          enabled: h.key?("enabled") ? h["enabled"] : true,
          insertion_order: h.key?("insertion_order") ? h["insertion_order"].to_i : 100,
          use_regex: h.key?("use_regex") ? h["use_regex"] : false,
          case_sensitive: h.key?("case_sensitive") ? h["case_sensitive"] : nil,
          constant: h.key?("constant") ? h["constant"] : nil,
          name: h["name"],
          priority: h.key?("priority") ? (h["priority"]&.to_i) : nil,
          id: h["id"],
          comment: h["comment"],
          selective: h.key?("selective") ? h["selective"] : nil,
          secondary_keys: h["secondary_keys"],
          position: h["position"],
        )
      end
    end
  end
end
