# frozen_string_literal: true

require "js_regex_to_ruby"
require_relative "engine/builder"
require_relative "engine/matcher"
require_relative "engine/injections"

module TavernKit
  module RisuAI
    module Lore
      # RisuAI lorebook scanning engine.
      #
      # Characterization source:
      # - resources/Risuai/src/ts/process/lorebook.svelte.ts (loadLoreBookV3Prompt)
      class Engine < TavernKit::Lore::Engine::Base
        Inject = Data.define(:operation, :location, :param, :lore)
        JS_REGEX_CACHE_MAX = 512
        JS_REGEX_MAX_INPUT_BYTES = 50_000

        Active = Data.define(
          :entry,           # TavernKit::Lore::Entry (original)
          :content,         # String (decorators stripped)
          :depth,           # Integer
          :position,        # String
          :role,            # Symbol (:system/:user/:assistant)
          :order,           # Integer
          :priority,        # Integer
          :tokens,          # Integer
          :source,          # String
          :inject,          # Inject, nil
          :scan_depth,      # Integer
          :full_word_match, # Boolean
          :dont_search_when_recursive, # Boolean
          :recursive_override,         # true/false/nil
          :force_state,                # :none/:activate/:deactivate
          :keep_activate_after_match,  # Boolean
          :dont_activate_after_match,  # Boolean
          :search_queries,             # Array<Hash>
        )

        def initialize(token_estimator: TavernKit::TokenEstimator.default, rng: Random.new)
          unless token_estimator.respond_to?(:estimate)
            raise ArgumentError, "token_estimator must respond to #estimate"
          end
          @token_estimator = token_estimator

          @rng = rng || Random.new
        end

        def scan(input)
          scan_input = normalize_input(input)
          warner = scan_input.warner if scan_input.respond_to?(:warner)
          warned = {}

          books = Array(scan_input.books).compact
          entries = books.flat_map { |b| Array(b&.entries) }.select { |e| e.is_a?(TavernKit::Lore::Entry) }

          return empty_result if entries.empty?

          messages = Array(scan_input.messages)
          global_scan_depth = scan_input.scan_depth.to_i
          global_full_word = scan_input.full_word_matching? == true
          global_recursive = scan_input.recursive_scanning? == true

          chat_length = scan_input.chat_length.to_i
          greeting_index = scan_input.greeting_index

          variables = scan_input.variables
          variables = TavernKit::VariablesStore::InMemory.new if variables.nil?

          budget_tokens = scan_input.budget
          budget_tokens = nil if budget_tokens.nil?
          budget_tokens = budget_tokens.to_i if budget_tokens

          recursive_prompts = []
          actives = []

          activated_ids = {}
          matching = true

          while matching
            matching = false

            entries.each_with_index do |entry, idx|
              next if activated_ids[idx]

              active = build_active(
                entry,
                chat_length: chat_length,
                greeting_index: greeting_index,
                global_scan_depth: global_scan_depth,
                global_full_word: global_full_word,
                variables: variables,
              )

              next unless active

              activated = active.entry.constant? || active.force_state != :none || active.force_state == :activate

              unless activated
                activated = matches_entry?(
                  entry: entry,
                  messages: messages,
                  recursive_prompts: recursive_prompts,
                  scan_depth: active.scan_depth,
                  full_word_matching: active.full_word_match,
                  dont_search_when_recursive: active.dont_search_when_recursive,
                  search_queries: active.search_queries,
                  warner: warner,
                  warned: warned,
                )
              end

              activated = true if active.force_state == :activate
              activated = false if active.force_state == :deactivate

              next unless activated

              actives << active
              activated_ids[idx] = true

              if active.keep_activate_after_match
                variables.set(internal_keep_key(active.entry), "true", scope: :global)
              end
              if active.dont_activate_after_match
                variables.set(internal_dont_key(active.entry), "true", scope: :global)
              end

              recursive =
                case active.recursive_override
                when true then true
                when false then false
                else
                  global_recursive
                end

              if recursive
                matching = true
                recursive_prompts << { source: active.source, data: active.content }
              end
            end
          end

          actives_sorted = actives.sort_by { |a| -a.priority.to_i }

          used_tokens = 0
          actives_filtered =
            if budget_tokens
              actives_sorted.select do |a|
                next false if (used_tokens + a.tokens.to_i) > budget_tokens

                used_tokens += a.tokens.to_i
                true
              end
            else
              actives_sorted.each { |a| used_tokens += a.tokens.to_i }
              actives_sorted
            end

          actives_resorted = actives_filtered.sort_by { |a| -a.order.to_i }

          injection_lores, actives_non_injection = actives_resorted.partition { |a| a.inject&.lore == true }

          apply_lore_injections!(actives_non_injection, injection_lores)

          activated_entries = actives_non_injection.reverse.map { |a| to_result_entry(a) }

          TavernKit::Lore::Result.new(
            activated_entries: activated_entries,
            total_tokens: used_tokens,
            trim_report: nil,
          )
        end

        private

        def normalize_input(input)
          return input if input.is_a?(TavernKit::RisuAI::Lore::ScanInput)

          TavernKit::RisuAI::Lore::ScanInput.new(
            messages: input.messages,
            books: input.books,
            budget: input.budget,
          )
        end

        def empty_result
          TavernKit::Lore::Result.new(activated_entries: [], total_tokens: 0, trim_report: nil)
        end
        # Instance helper methods are split into:
        # - `risu_ai/lore/engine/builder.rb`
        # - `risu_ai/lore/engine/matcher.rb`
        # - `risu_ai/lore/engine/injections.rb`
      end
    end
  end
end
