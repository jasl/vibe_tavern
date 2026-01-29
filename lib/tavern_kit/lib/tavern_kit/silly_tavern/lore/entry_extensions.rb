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

        def outlet_name
          @memo[:outlet_name] ||= TavernKit::Utils.presence(@ext[:outlet_name])
        end
      end
    end
  end
end
