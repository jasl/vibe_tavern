# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      # Thin, typed accessors for SillyTavern-specific lore entry fields.
      #
      # Pattern: keep Core value objects (TavernKit::Lore::Entry) CCv2/CCv3-only,
      # store platform-only fields in `entry.extensions`, and expose them through
      # a platform wrapper like this one. RisuAI should follow the same pattern.
      class EntryExtensions
        SELECTIVE_LOGIC = {
          0 => :and_any,
          1 => :not_all,
          2 => :not_any,
          3 => :and_all,
        }.freeze

        def self.wrap(entry) = new(entry)

        def initialize(entry)
          @ext = TavernKit::Utils::HashAccessor.wrap(entry.respond_to?(:extensions) ? entry.extensions : {})
          @memo = {}
        end

        # --- Match flags (non-chat scan sources) ---

        def match_persona_description? = @ext.bool(:match_persona_description, default: false)
        def match_character_description? = @ext.bool(:match_character_description, default: false)
        def match_character_personality? = @ext.bool(:match_character_personality, default: false)
        def match_character_depth_prompt? = @ext.bool(:match_character_depth_prompt, default: false)
        def match_scenario? = @ext.bool(:match_scenario, default: false)
        def match_creator_notes? = @ext.bool(:match_creator_notes, default: false)

        def match_non_chat_data?
          match_persona_description? ||
            match_character_description? ||
            match_character_personality? ||
            match_character_depth_prompt? ||
            match_scenario? ||
            match_creator_notes?
        end

        # --- Character filtering ---

        def character_filter_names
          @memo[:character_filter_names] ||= Array(@ext[:character_filter_names]).map(&:to_s).freeze
        end

        def character_filter_tags
          @memo[:character_filter_tags] ||= Array(@ext[:character_filter_tags]).map(&:to_s).freeze
        end

        def character_filter_exclude? = @ext.bool(:character_filter_exclude, default: false)

        def has_character_filter?
          character_filter_names.any? || character_filter_tags.any?
        end

        # Returns true if entry matches the given character (by name or tags).
        # If no filter is configured, matches all characters.
        def matches_character?(character_name: nil, character_tags: nil)
          return true unless has_character_filter?

          name_matched =
            if character_filter_names.any?
              character_name && character_filter_names.include?(character_name)
            else
              false
            end

          tag_matched =
            if character_filter_tags.any?
              Array(character_tags).any? { |tag| character_filter_tags.include?(tag.to_s) }
            else
              false
            end

          base_match = name_matched || tag_matched
          character_filter_exclude? ? !base_match : base_match
        end

        # --- Generation type triggers ---

        def triggers
          @memo[:triggers] ||= TavernKit::Coerce.triggers(@ext[:triggers])
        end

        def has_triggers? = triggers.any?

        def triggered_by?(trigger_type)
          t = triggers
          return true if t.empty?

          t.include?(TavernKit::Coerce.generation_type(trigger_type))
        end

        # --- Misc ST routing fields ---

        def use_probability? = @ext.bool(:use_probability, default: true)

        def probability
          raw = @ext[:probability]
          p = raw.nil? ? 100 : raw.to_i
          [[p, 0].max, 100].min
        end

        def outlet_name
          @memo[:outlet_name] ||= TavernKit::Utils.presence(@ext[:outlet_name])
        end

        # --- In-chat insertion fields (at_depth / outlet) ---

        def depth
          # ST default depth is 4.
          @ext.int(:depth, default: 4)
        end

        def role
          TavernKit::Coerce.role(@ext[:role], default: :system)
        end

        # --- Selective logic ---

        def selective_logic
          raw = @ext[:selective_logic]
          return :and_any if raw.nil?

          if raw.is_a?(Integer)
            SELECTIVE_LOGIC[raw] || :and_any
          else
            s = raw.to_s.strip
            return :and_any if s.empty?

            if s.match?(/\A\d+\z/)
              SELECTIVE_LOGIC[s.to_i] || :and_any
            else
              sym = TavernKit::Utils.underscore(s).to_sym
              SELECTIVE_LOGIC.value?(sym) ? sym : :and_any
            end
          end
        end

        # --- Budget + recursion flags ---

        def ignore_budget? = @ext.bool(:ignore_budget, default: false)
        def exclude_recursion? = @ext.bool(:exclude_recursion, default: false)
        def prevent_recursion? = @ext.bool(:prevent_recursion, default: false)

        def delay_until_recursion_level
          raw = @ext[:delay_until_recursion]
          return nil if raw.nil? || raw == false
          return 1 if raw == true

          s = raw.to_s.strip
          return nil if s.empty?

          i = s.to_i
          i.positive? ? i : 1
        end

        def delay_until_recursion? = !delay_until_recursion_level.nil?

        # --- Per-entry scan tuning ---

        def scan_depth
          raw = @ext[:scan_depth]
          return nil if raw.nil?

          s = raw.to_s.strip
          return nil if s.empty?

          s.to_i
        end

        def match_whole_words
          raw = @ext[:match_whole_words]
          return nil if raw.nil?

          @ext.bool(:match_whole_words, default: false)
        end

        # --- Timed effects ---

        def sticky
          positive_int(:sticky)
        end

        def cooldown
          positive_int(:cooldown)
        end

        def delay
          positive_int(:delay)
        end

        # --- Inclusion groups ---

        def group
          @memo[:group] ||= TavernKit::Utils.presence(@ext[:group])
        end

        def group_names
          @memo[:group_names] ||= Array(group&.split(/,\s*/)).map(&:to_s).map(&:strip).reject(&:empty?).uniq.freeze
        end

        def group_override? = @ext.bool(:group_override, default: false)

        def group_weight
          raw = @ext[:group_weight]
          w = raw.nil? ? 100 : raw.to_i
          [w, 1].max
        end

        # nil means "inherit global setting"
        def use_group_scoring
          raw = @ext[:use_group_scoring]
          return nil if raw.nil?

          @ext.bool(:use_group_scoring, default: false)
        end

        private

        def positive_int(key)
          raw = @ext[key]
          return nil if raw.nil?

          i = raw.to_i
          i.positive? ? i : nil
        end
      end
    end
  end
end
