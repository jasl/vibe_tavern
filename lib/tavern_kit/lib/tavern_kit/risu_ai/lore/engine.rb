# frozen_string_literal: true

require "js_regex_to_ruby"

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
          variables = TavernKit::ChatVariables::InMemory.new if variables.nil?

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

        def internal_keep_key(entry)
          suffix = entry.id.to_s
          if suffix.empty?
            suffix = TavernKit::RisuAI::Utils.pick_hash_rand(5555, entry.content).to_s
          end
          "__internal_ka_#{suffix}"
        end

        def internal_dont_key(entry)
          suffix = entry.id.to_s
          if suffix.empty?
            suffix = TavernKit::RisuAI::Utils.pick_hash_rand(5555, entry.content).to_s
          end
          "__internal_da_#{suffix}"
        end

        def build_active(entry, chat_length:, greeting_index:, global_scan_depth:, global_full_word:, variables:)
          h = entry.to_h
          ext = TavernKit::Utils::HashAccessor.wrap(h.fetch("extensions", {}))

          mode = ext.fetch(:mode, default: nil)
          return nil if mode.to_s == "folder"

          activated = entry.enabled?
          position = ""
          depth = 0
          scan_depth = global_scan_depth
          role = :system
          order = entry.insertion_order.to_i
          priority = order
          force_state = :none
          search_queries = []
          full_word = global_full_word
          dont_search_when_recursive = false
          recursive_override = nil
          keep_activate_after_match = false
          dont_activate_after_match = false
          inject = nil

          parsed = TavernKit::RisuAI::Lore::DecoratorParser.parse(entry.content) do |name, args|
            case name
            when "end"
              position = "depth"
              depth = 0
              nil
            when "activate_only_after"
              int = safe_int(args[0])
              return false if int.nil?

              activated = false if chat_length < int
              nil
            when "activate_only_every"
              int = safe_int(args[0])
              return false if int.nil?

              activated = false if int.positive? && (chat_length % int) != 0
              nil
            when "keep_activate_after_match"
              if variables.get(internal_keep_key(entry), scope: :global).to_s == "true"
                force_state = :activate
              else
                keep_activate_after_match = true
              end
              false
            when "dont_activate_after_match"
              if variables.get(internal_dont_key(entry), scope: :global).to_s == "true"
                force_state = :deactivate
              else
                dont_activate_after_match = true
              end
              false
            when "depth"
              int = safe_int(args[0])
              return false if int.nil?

              depth = int
              position = "depth"
              nil
            when "reverse_depth"
              int = safe_int(args[0])
              return false if int.nil?

              depth = int
              position = "reverse_depth"
              nil
            when "instruct_depth", "reverse_instruct_depth", "instruct_scan_depth"
              false
            when "role"
              v = args[0].to_s
              return false unless %w[user assistant system].include?(v)

              role = v.to_sym
              nil
            when "scan_depth"
              int = safe_int(args[0])
              return false if int.nil?

              scan_depth = int
              nil
            when "is_greeting"
              int = safe_int(args[0])
              return false if int.nil?

              # Upstream uses (fmIndex + 1) compared to int.
              if greeting_index.nil? || (greeting_index.to_i + 1) != int
                activated = false
              end
              nil
            when "position"
              v = args[0].to_s
              return false unless v.start_with?("pt_") || %w[after_desc before_desc personality scenario].include?(v)

              position = v
              nil
            when "inject_lore"
              inject ||= Inject.new(operation: :append, location: "", param: "", lore: true)
              inject = inject.with(location: args.join(" "), lore: true)
              nil
            when "inject_at"
              inject ||= Inject.new(operation: :append, location: "", param: "", lore: false)
              inject = inject.with(location: args.join(" "), lore: false)
              nil
            when "inject_replace"
              inject ||= Inject.new(operation: :replace, location: "", param: "", lore: false)
              inject = inject.with(operation: :replace, param: args.join(" "))
              nil
            when "inject_prepend"
              inject ||= Inject.new(operation: :prepend, location: "", param: "", lore: false)
              inject = inject.with(operation: :prepend, param: args.join(" "))
              nil
            when "ignore_on_max_context"
              priority = -1000
              nil
            when "additional_keys"
              search_queries << { keys: args, negative: false }
              nil
            when "exclude_keys"
              search_queries << { keys: args, negative: true }
              nil
            when "exclude_keys_all"
              search_queries << { keys: args, negative: true, all: true }
              nil
            when "match_full_word"
              full_word = true
              nil
            when "match_partial_word"
              full_word = false
              nil
            when "activate"
              force_state = :activate
              nil
            when "dont_activate"
              force_state = :deactivate
              nil
            when "probability"
              pct = safe_int(args[0])
              return false if pct.nil?

              activated = false if (@rng.rand * 100) > pct
              nil
            when "priority"
              int = safe_int(args[0])
              return false if int.nil?

              priority = int
              nil
            when "unrecursive"
              recursive_override = false
              nil
            when "recursive"
              recursive_override = true
              nil
            when "no_recursive_search"
              dont_search_when_recursive = true
              nil
            else
              false
            end
          end

          return nil unless activated

          cleaned = parsed.content.to_s
          tokens = @token_estimator.estimate(cleaned)

          Active.new(
            entry: entry,
            content: cleaned,
            depth: depth,
            position: position,
            role: role,
            order: order,
            priority: priority,
            tokens: tokens.to_i,
            source: entry.comment.to_s.empty? ? (entry.name.to_s.empty? ? "lorebook" : entry.name.to_s) : entry.comment.to_s,
            inject: inject,
            scan_depth: scan_depth.to_i,
            full_word_match: full_word == true,
            dont_search_when_recursive: dont_search_when_recursive == true,
            recursive_override: recursive_override,
            force_state: force_state,
            keep_activate_after_match: keep_activate_after_match == true,
            dont_activate_after_match: dont_activate_after_match == true,
            search_queries: search_queries,
          )
        end

        def safe_int(value)
          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end

        def matches_entry?(
          entry:,
          messages:,
          recursive_prompts:,
          scan_depth:,
          full_word_matching:,
          dont_search_when_recursive:,
          search_queries:,
          warner:,
          warned:
        )
          # Primary keys are required unless the entry is always active (handled elsewhere).
          primary = Array(entry.keys).map(&:to_s)
          return false if primary.empty?

          queries = Array(search_queries).map { |q| q.is_a?(Hash) ? q : {} }.dup
          queries << { keys: primary, negative: false }

          if entry.selective? && Array(entry.secondary_keys).any?
            queries << { keys: Array(entry.secondary_keys).map(&:to_s), negative: false }
          end

          queries.all? do |query|
            q = normalize_hash_keys(query)
            keys = Array(q[:keys]).map(&:to_s)
            negative = q[:negative]
            all_mode = q[:all]

            result = search_match?(
              messages: messages,
              recursive_prompts: recursive_prompts,
              keys: keys,
              search_depth: scan_depth,
              regex: entry.regex?,
              full_word_matching: full_word_matching,
              all: all_mode == true,
              dont_search_when_recursive: dont_search_when_recursive,
              warner: warner,
              warned: warned,
            )

            negative == true ? !result : result
          end
        end

        def search_match?(messages:, recursive_prompts:, keys:, search_depth:, regex:, full_word_matching:, all:, dont_search_when_recursive:, warner:, warned:)
          depth = search_depth.to_i
          depth = 0 if depth.negative?

          keys = Array(keys).map { |k| k.to_s.strip }.reject(&:empty?)
          return false if keys.empty?

          sliced = Array(messages).last(depth)

          m_list = sliced.map { |m| normalize_message(m) }
          unless dont_search_when_recursive
            m_list.concat(Array(recursive_prompts).map { |h| normalize_recursive_prompt(h) })
          end

          if regex
            return false unless keys.all? { |k| k.start_with?("/") }

            keys.any? do |js_re|
              re = cached_js_regex(js_re)
              unless re
                warn_once(warner, warned, [:js_regex_invalid, js_re], "Invalid JS regex literal: #{truncate_literal(js_re)}")
                next false
              end

              m_list.any? do |m|
                begin
                  re.match?(m[:data])
                rescue Regexp::TimeoutError
                  warn_once(warner, warned, [:js_regex_timeout, js_re], "JS regex match timed out: #{truncate_literal(js_re)}")
                  false
                end
              end
            end
          else
            normalized = m_list.map do |m|
              data = strip_macro_comments(m[:data].to_s.downcase)
              { data: data, original: m }
            end

            all_mode_matched = true

            normalized.each do |m|
              if full_word_matching
                words = m[:data].split(/ /)
                keys.each do |key|
                  k2 = key.to_s.downcase
                  if words.include?(k2)
                    return true unless all
                  else
                    all_mode_matched = false if all
                  end
                end
              else
                text = m[:data].gsub(" ", "")
                keys.each do |key|
                  k2 = key.to_s.downcase.gsub(" ", "")
                  if text.include?(k2)
                    return true unless all
                  else
                    all_mode_matched = false if all
                  end
                end
              end
            end

            all && all_mode_matched
          end
        end

        def strip_macro_comments(text)
          s = text.to_s
          s = s.gsub(/\{\{\/\/(.+?)\}\}/, "")
          s.gsub(/\{\{comment:(.+?)\}\}/, "")
        end

        def warn_once(warner, warned, key, message)
          return nil unless warner&.respond_to?(:call)

          if warned.is_a?(Hash)
            return nil if warned[key]

            warned[key] = true
          end

          warner.call(message.to_s)
          nil
        end

        def truncate_literal(value, max_len: 200)
          s = value.to_s
          return s if s.length <= max_len

          "#{s[0, max_len]}..."
        rescue StandardError
          ""
        end

        def cached_js_regex(value)
          v = value.to_s
          return nil unless v.start_with?("/")

          @js_regex_cache ||= TavernKit::JsRegexCache.new(max_size: JS_REGEX_CACHE_MAX)
          @js_regex_cache.fetch(v)
        end

        def normalize_message(message)
          if message.is_a?(Hash)
            h = normalize_hash_keys(message)
            data = h[:data] || h[:content] || h[:text]
            { data: data.to_s }
          else
            { data: message.to_s }
          end
        end

        def normalize_recursive_prompt(hash)
          h = normalize_hash_keys(hash)
          data = h[:data] || h[:prompt]
          { data: data.to_s }
        end

        def normalize_hash_keys(raw)
          h = raw.is_a?(Hash) ? raw : {}
          return {} if h.empty?

          snake_symbol = true
          h.each_key do |key|
            unless key.is_a?(Symbol) && key.to_s.match?(/\A[a-z0-9_]+\z/)
              snake_symbol = false
              break
            end
          end
          return h if snake_symbol

          TavernKit::Runtime::Base.normalize(h)
        end

        def apply_lore_injections!(actives, injection_lores)
          list = Array(actives)

          Array(injection_lores).each do |lore|
            inject = lore.inject
            next unless inject

            idx = list.index { |a| a.source.to_s == inject.location.to_s }
            next unless idx

            found = list[idx]
            updated_content =
              case inject.operation
              when :append
                [found.content, lore.content].join(" ").strip
              when :prepend
                [lore.content, found.content].join(" ").strip
              when :replace
                found.content.to_s.gsub(inject.param.to_s, lore.content.to_s)
              else
                found.content
              end

            list[idx] = found.with(content: updated_content)
          end
        end

        def to_result_entry(active)
          base = active.entry

          ext = base.extensions.dup
          ext["risuai"] ||= {}

          risu = ext["risuai"].is_a?(Hash) ? ext["risuai"].dup : {}
          risu["depth"] = active.depth
          risu["role"] = active.role.to_s
          risu["source"] = active.source
          if active.inject
            risu["inject"] = {
              "operation" => active.inject.operation.to_s,
              "location" => active.inject.location,
              "param" => active.inject.param,
              "lore" => active.inject.lore,
            }
          end
          ext["risuai"] = risu

          TavernKit::Lore::Entry.new(
            keys: base.keys,
            content: active.content,
            enabled: true,
            insertion_order: base.insertion_order,
            use_regex: base.use_regex,
            case_sensitive: base.case_sensitive,
            constant: base.constant,
            name: base.name,
            priority: base.priority,
            id: base.id,
            comment: base.comment,
            selective: base.selective,
            secondary_keys: base.secondary_keys,
            position: active.position,
            extensions: ext,
          )
        end
      end
    end
  end
end
