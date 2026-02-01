# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      class Engine < TavernKit::Lore::Engine::Base
        # Group filtering + scoring helpers (ST-like inclusion groups).
        #
        # Pure refactor: extracted from `silly_tavern/lore/engine.rb` (Wave 6 large-file split).

        private

        def filter_by_inclusion_groups!(entries, already_activated:, buffer:, scan_state:, timed_effects:)
          grouped = {}

          entries.each do |se|
            next if se.ext.group_names.empty?

            se.ext.group_names.each do |name|
              (grouped[name] ||= []) << se
            end
          end

          return if grouped.empty?

          has_sticky = {}

          grouped.each do |name, group|
            has_sticky[name] = false

            sticky_entries = group.select { |se| timed_effects.sticky_active?(se.entry.id.to_s) }
            if sticky_entries.any?
              group.dup.each do |se|
                next if sticky_entries.include?(se)

                entries.delete(se)
                group.delete(se)
              end
              has_sticky[name] = true
            end

            group.dup.each do |se|
              if timed_effects.cooldown_active?(se.entry.id.to_s) || timed_effects.delay_active?(se.entry)
                entries.delete(se)
                group.delete(se)
              end
            end
          end

          filter_groups_by_scoring!(grouped, entries, buffer, scan_state, has_sticky)

          grouped.each do |name, group|
            next if has_sticky[name]

            if already_activated.any? { |se| se.ext.group.to_s == name }
              group.each { |se| entries.delete(se) }
              next
            end

            next if group.length <= 1

            prios = group.select { |se| se.ext.group_override? }.sort_by { |se| [-se.order, se.entry.id.to_s] }
            if prios.any?
              winner = prios.first
              group.each { |se| entries.delete(se) unless se == winner }
              next
            end

            total_weight = group.sum { |se| se.ext.group_weight }
            roll = @rng.rand * total_weight
            current = 0
            winner = nil

            group.each do |se|
              current += se.ext.group_weight
              if roll <= current
                winner = se
                break
              end
            end

            group.each { |se| entries.delete(se) unless se == winner }
          end
        end

        def filter_groups_by_scoring!(grouped, entries, buffer, scan_state, has_sticky)
          grouped.each do |name, group|
            next if group.empty?
            next if has_sticky[name]

            any_entry_scored = group.any? do |se|
              explicit = se.ext.use_group_scoring
              explicit == true
            end

            next unless @use_group_scoring || any_entry_scored

            scores = group.map { |se| buffer.score(se, scan_state, case_sensitive: case_sensitive(se), match_whole_words: match_whole_words(se)) }
            max_score = scores.max || 0

            group.each_with_index do |se, idx|
              explicit = se.ext.use_group_scoring
              is_scored = explicit.nil? ? @use_group_scoring : explicit
              next unless is_scored

              next unless scores[idx] < max_score

              entries.delete(se)
            end

            group.reject! { |se| !entries.include?(se) }
          end
        end
      end
    end
  end
end
