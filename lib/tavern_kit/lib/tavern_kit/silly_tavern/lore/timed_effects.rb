# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      # Manages SillyTavern World Info timed effects (sticky/cooldown/delay).
      #
      # State shape (mutable Hash, application-owned):
      #   timed_state[entry_id] = {
      #     sticky:   { start_turn: Integer, end_turn: Integer, protected: Boolean },
      #     cooldown: { start_turn: Integer, end_turn: Integer, protected: Boolean },
      #   }
      #
      # Notes:
      # - "delay" is a per-entry field (suppresses activation until turn_count >= delay)
      # - "protected" follows ST semantics: when turn_count <= start_turn, non-protected
      #   effects are removed to avoid repeating effects when chat has not advanced.
      class TimedEffects
        EFFECT_TYPES = %i[sticky cooldown].freeze

        def initialize(turn_count:, entries:, timed_state:, dry_run: false)
          @turn_count = turn_count.to_i
          @entries = Array(entries)
          @timed_state = timed_state.is_a?(Hash) ? timed_state : {}
          @dry_run = dry_run == true
          @active = { sticky: {}, cooldown: {}, delay: {} }
        end

        attr_reader :turn_count, :timed_state, :active

        def check!
          ensure_state_structure!

          entries_by_id = @entries.each_with_object({}) do |entry, map|
            id = entry.respond_to?(:id) ? entry.id : nil
            map[id.to_s] = entry if id
          end

          EFFECT_TYPES.each do |type|
            @timed_state.each do |entry_id, state|
              next unless state.is_a?(Hash)

              effect = state[type] || state[type.to_s]
              next unless effect.is_a?(Hash)

              start_turn = (effect[:start_turn] || effect["start_turn"] || effect[:start] || effect["start"]).to_i
              end_turn = (effect[:end_turn] || effect["end_turn"] || effect[:end] || effect["end"]).to_i
              protected_flag = !!(effect[:protected] || effect["protected"])

              # Drop if chat has not advanced since setting and not protected.
              if @turn_count <= start_turn && !protected_flag
                state.delete(type)
                state.delete(type.to_s)
                next
              end

              entry = entries_by_id[entry_id.to_s]

              # If entry is missing, keep until end passed (ST parity).
              if entry.nil?
                if @turn_count >= end_turn
                  state.delete(type)
                  state.delete(type.to_s)
                end
                next
              end

              ext = EntryExtensions.wrap(entry)

              configured = case type
              when :sticky then !ext.sticky.nil?
              when :cooldown then !ext.cooldown.nil?
              else false
              end

              unless configured
                state.delete(type)
                state.delete(type.to_s)
                next
              end

              if @turn_count >= end_turn
                state.delete(type)
                state.delete(type.to_s)
                on_ended(type, entry)
                next
              end

              @active[type][entry_id.to_s] = true
            end
          end

          @entries.each do |entry|
            next unless delay_active?(entry)

            @active[:delay][entry.id.to_s] = true if entry.respond_to?(:id)
          end

          self
        end

        def sticky_active?(entry_id)
          @active[:sticky].key?(entry_id.to_s)
        end

        def cooldown_active?(entry_id)
          @active[:cooldown].key?(entry_id.to_s)
        end

        def delay_active?(entry)
          ext = EntryExtensions.wrap(entry)
          d = ext.delay
          return false if d.nil?

          @turn_count < d.to_i
        end

        # Persist sticky/cooldown effects for newly activated entries.
        #
        # ST behavior: only sets effects when the entry defines the effect,
        # and does not overwrite existing metadata for the same entry id.
        def set_effects!(activated_entries)
          return self if @dry_run

          ensure_state_structure!

          Array(activated_entries).each do |entry|
            next unless entry.respond_to?(:id)

            entry_id = entry.id.to_s
            state = (@timed_state[entry_id] ||= {})
            state = (@timed_state[entry_id] = {}) unless state.is_a?(Hash)

            ext = EntryExtensions.wrap(entry)
            set_type_effect!(state, :sticky, duration: ext.sticky, protected_flag: false)
            set_type_effect!(state, :cooldown, duration: ext.cooldown, protected_flag: false)
          end

          self
        end

        private

        def ensure_state_structure!
          @timed_state.each do |entry_id, state|
            next if state.is_a?(Hash)

            @timed_state[entry_id] = {}
          end
        end

        def on_ended(type, entry)
          return if @dry_run
          return unless type == :sticky

          ext = EntryExtensions.wrap(entry)
          cd = ext.cooldown
          return if cd.nil?

          entry_id = entry.id.to_s
          state = (@timed_state[entry_id] ||= {})
          state = (@timed_state[entry_id] = {}) unless state.is_a?(Hash)

          # ST: cooldown starts *after* sticky ends and overwrites any existing cooldown metadata.
          effect = build_effect(duration: cd, protected_flag: true)
          state[:cooldown] = effect
          @active[:cooldown][entry_id] = true
        end

        def set_type_effect!(state, type, duration:, protected_flag:)
          return if duration.nil?

          state[type] ||= build_effect(duration: duration, protected_flag: protected_flag)
        end

        def build_effect(duration:, protected_flag:)
          d = duration.to_i
          {
            start_turn: @turn_count,
            end_turn: @turn_count + d,
            protected: !!protected_flag,
          }
        end
      end
    end
  end
end
