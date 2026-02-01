# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      # Internal class methods for `Engine`.
      #
      # Pure refactor: extracted from `silly_tavern/lore/engine.rb` (Wave 6 large-file split).
      class Engine < TavernKit::Lore::Engine::Base
        def self.sort_entries(global:, character:, chat:, persona:, strategy:)
          sort_fn = lambda do |list|
            Array(list).sort_by do |entry|
              order =
                if entry.respond_to?(:insertion_order)
                  entry.insertion_order
                elsif entry.is_a?(Hash)
                  TavernKit::Utils::HashAccessor.wrap(entry).fetch(:order, :insertion_order, :insertionOrder, default: 0).to_i
                else
                  0
                end

              -order.to_i
            end
          end

          global_sorted = sort_fn.call(global)
          char_sorted = sort_fn.call(character)

          base =
            case strategy.to_sym
            when :character_lore_first, :character_first
              char_sorted + global_sorted
            when :global_lore_first, :global_first
              global_sorted + char_sorted
            when :evenly
              sort_fn.call(global_sorted + char_sorted)
            else
              sort_fn.call(global_sorted + char_sorted)
            end

          sort_fn.call(chat) + sort_fn.call(persona) + base
        end

        def self.match_entry(entry, text, case_sensitive: false, match_whole_words: true)
          h = entry.is_a?(Hash) ? entry : entry.respond_to?(:to_h) ? entry.to_h : {}
          ha = TavernKit::Utils::HashAccessor.wrap(h)

          keys = Array(ha.fetch(:keys, default: [])).map(&:to_s)
          return false if keys.empty?

          scan = text.to_s
          scan_downcase = case_sensitive ? nil : scan.downcase
          primary_matched =
            keys.any? do |k|
              Buffer.match_pre_normalized?(scan, scan_downcase, k, nil, case_sensitive: case_sensitive, match_whole_words: match_whole_words)
            end
          return false unless primary_matched

          selective = ha.bool(:selective, default: false)
          secondary = Array(ha.fetch(:secondary_keys, :secondaryKeys, default: [])).map(&:to_s).map(&:strip).reject(&:empty?)
          return true unless selective == true && secondary.any?

          ext = TavernKit::Utils::HashAccessor.wrap(ha.fetch(:extensions, default: {}))
          logic =
            case ext.fetch(:selective_logic, :selectiveLogic, default: nil)
            when 0, "0" then :and_any
            when 1, "1" then :not_all
            when 2, "2" then :not_any
            when 3, "3" then :and_all
            else
              raw = ext.fetch(:selective_logic, :selectiveLogic, default: nil)
              raw.nil? ? :and_any : TavernKit::Utils.underscore(raw).to_sym
            end

          has_any = false
          has_all = true

          secondary.each do |key|
            matched = Buffer.match_pre_normalized?(scan, scan_downcase, key, nil, case_sensitive: case_sensitive, match_whole_words: match_whole_words)

            has_any ||= matched
            has_all &&= matched

            return true if logic == :and_any && matched
            return true if logic == :not_all && !matched
          end

          return true if logic == :not_any && !has_any
          return true if logic == :and_all && has_all

          false
        end

        def self.apply_budget(entries:, max_context:, budget_percent:, budget_cap: 0)
          list = Array(entries)
          max = max_context.to_i
          pct = budget_percent.to_f
          cap = budget_cap.to_i

          budget = (pct * max / 100.0).round
          budget = 1 if budget <= 0
          budget = cap if cap.positive? && budget > cap

          used = 0
          list.filter_map do |entry|
            h = entry.is_a?(Hash) ? entry : entry.respond_to?(:to_h) ? entry.to_h : {}
            ha = TavernKit::Utils::HashAccessor.wrap(h)
            tokens = ha.fetch(:tokens, default: 0).to_i
            ignore = ha.bool(:ignore_budget, :ignoreBudget, default: false)

            if ignore
              used += tokens
              entry
            elsif (used + tokens) >= budget
              nil
            else
              used += tokens
              entry
            end
          end
        end

        def self.scan_state(entry, recursion:, current_delay_level: 1)
          h = entry.is_a?(Hash) ? entry : entry.respond_to?(:to_h) ? entry.to_h : {}
          ha = TavernKit::Utils::HashAccessor.wrap(h)
          ext = TavernKit::Utils::HashAccessor.wrap(ha.fetch(:extensions, default: {}))

          exclude_recursion = ext.bool(:exclude_recursion, :excludeRecursion, default: false)
          delay_raw = ext.fetch(:delay_until_recursion, :delayUntilRecursion, default: nil)

          delay_level =
            if delay_raw.nil? || delay_raw == false
              nil
            elsif delay_raw == true
              1
            else
              i = delay_raw.to_i
              i.positive? ? i : 1
            end

          if recursion == true
            return :excluded if exclude_recursion == true
            return :delayed if delay_level && delay_level.to_i > current_delay_level.to_i

            :eligible
          else
            delay_level ? :delayed : :eligible
          end
        end
      end
    end
  end
end
