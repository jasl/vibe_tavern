# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      # SillyTavern-specific scan input for World Info processing.
      #
      # Extends the base ScanInput with ST-specific fields required for:
      # - Non-chat data scanning (persona, character description, etc.)
      # - Generation type triggers
      # - Character filtering
      # - Timed effects (sticky/cooldown/delay)
      # - Forced activations and minimum activations
      #
      # == Scan Context
      #
      # The +scan_context+ hash provides non-chat data that entries can opt
      # into matching against. Entries must explicitly set their +match_*+
      # flags to include these in keyword scanning.
      #
      # == Timed State
      #
      # The +timed_state+ tracks sticky/cooldown/delay effects across turns.
      # It's a hash keyed by entry UID with start/end turn indices.
      #
      # == Example Usage
      #
      #   input = SillyTavern::Lore::ScanInput.new(
      #     messages: chat_messages,
      #     books: [character_book, global_book],
      #     budget: 2000,
      #     scan_context: {
      #       persona_description: "A brave knight...",
      #       character_description: "...",
      #     },
      #     trigger: :normal,
      #     character_name: "Alice",
      #     character_tags: ["fantasy", "female"],
      #   )
      #
      class ScanInput < TavernKit::Lore::ScanInput
        # @return [Hash] Non-chat data for keyword matching.
        #   Keys: :persona_description, :character_description,
        #         :character_personality, :character_depth_prompt,
        #         :scenario, :creator_notes
        attr_reader :scan_context

        # @return [Array<String>] Additional injection prompts (Author's Note, extensions).
        attr_reader :scan_injects

        # @return [Symbol] Current generation type (:normal, :continue, :impersonate, :swipe, :quiet).
        attr_reader :trigger

        # @return [Hash] Timed effect state keyed by entry id.
        #   ST key form is typically "world.uid" (see SillyTavern::Lore::Engine id namespacing).
        #   Values are hashes with :sticky, :cooldown, :delay tracking.
        attr_reader :timed_state

        # @return [String, nil] Current character name for filtering.
        attr_reader :character_name

        # @return [Array<String>] Current character tags for filtering.
        attr_reader :character_tags

        # @return [Array<String>] Entry ids to force activate regardless of keyword matching.
        #   ST key form is typically "world.uid" (see SillyTavern::Lore::Engine id namespacing).
        attr_reader :forced_activations

        # @return [Integer] Minimum number of entries to activate.
        attr_reader :min_activations

        # @return [Integer] Maximum depth for min_activations scoring.
        attr_reader :min_activations_depth_max

        # @return [Integer] Current turn count for timed effect calculations.
        attr_reader :turn_count

        def initialize(
          messages:,
          books:,
          budget:,
          warner: nil,
          scan_context: {},
          scan_injects: [],
          trigger: :normal,
          timed_state: {},
          character_name: nil,
          character_tags: [],
          forced_activations: [],
          min_activations: 0,
          min_activations_depth_max: 0,
          turn_count: 0,
          **_platform_attrs
        )
          super(messages: messages, books: books, budget: budget, warner: warner)

          @scan_context = normalize_scan_context(scan_context)
          @scan_injects = Array(scan_injects).map(&:to_s).freeze
          @trigger = trigger.is_a?(Symbol) ? trigger : trigger.to_s.to_sym
          # Application-owned mutable state. TimedEffects updates this in-place.
          @timed_state = timed_state.is_a?(Hash) ? timed_state : {}
          @character_name = character_name&.to_s
          @character_tags = Array(character_tags).map(&:to_s).freeze
          @forced_activations = Array(forced_activations).map(&:to_s).freeze
          @min_activations = min_activations.to_i
          @min_activations_depth_max = min_activations_depth_max.to_i
          @turn_count = turn_count.to_i
        end

        # Returns true if entry should be force-activated.
        # @param entry_uid [String] Entry id (typically "world.uid")
        # @return [Boolean]
        def force_activate?(entry_uid)
          forced_activations.include?(entry_uid.to_s)
        end

        # Returns the scan context value for the given key.
        # @param key [Symbol] One of the scan context keys
        # @return [String, nil]
        def context_value(key)
          scan_context[key.to_sym]
        end

        # Returns all non-empty scan context values as an array.
        # Used for building the combined scan buffer.
        # @return [Array<String>]
        def context_values
          scan_context.values.reject { |v| v.nil? || v.empty? }
        end

        # Returns true if the entry's trigger matches the current trigger.
        # @param entry [TavernKit::Lore::Entry]
        # @return [Boolean]
        def entry_triggered?(entry)
          EntryExtensions.wrap(entry).triggered_by?(trigger)
        end

        # Returns true if the entry matches the current character filter.
        # @param entry [TavernKit::Lore::Entry]
        # @return [Boolean]
        def entry_matches_character?(entry)
          EntryExtensions.wrap(entry).matches_character?(
            character_name: character_name,
            character_tags: character_tags,
          )
        end

        # Checks if an entry is currently in a sticky activation period.
        # @param entry_uid [String]
        # @return [Boolean]
        def sticky_active?(entry_uid)
          effect = timed_effect(entry_uid, :sticky)
          return false unless effect

          turn_count < effect_end_turn(effect)
        end

        # Checks if an entry is currently in cooldown.
        # @param entry_uid [String]
        # @return [Boolean]
        def cooldown_active?(entry_uid)
          effect = timed_effect(entry_uid, :cooldown)
          return false unless effect

          turn_count < effect_end_turn(effect)
        end

        # Checks if an entry has a delay that hasn't elapsed.
        # @param entry_uid [String]
        # @return [Boolean]
        def delay_active?(entry_uid)
          effect = timed_effect(entry_uid, :delay)
          return false unless effect

          start_turn = (effect[:start_turn] || effect["start_turn"] || 0).to_i
          duration = (effect[:duration] || effect["duration"] || 0).to_i
          turn_count < start_turn + duration
        end

        private

        SCAN_CONTEXT_KEYS = %i[
          persona_description
          character_description
          character_personality
          character_depth_prompt
          scenario
          creator_notes
        ].freeze

        def normalize_scan_context(context)
          return {} unless context.is_a?(Hash)

          normalized = {}
          context.each do |key, value|
            sym_key = key.to_sym
            next unless SCAN_CONTEXT_KEYS.include?(sym_key)

            normalized[sym_key] = value&.to_s
          end
          normalized.freeze
        end

        def timed_effect(entry_uid, type)
          state = timed_state[entry_uid.to_s]
          return nil unless state.is_a?(Hash)

          effect = state[type] || state[type.to_s]
          effect.is_a?(Hash) ? effect : nil
        end

        def effect_end_turn(effect)
          (effect[:end_turn] || effect["end_turn"] || effect[:end] || effect["end"] || 0).to_i
        end
      end
    end
  end
end
