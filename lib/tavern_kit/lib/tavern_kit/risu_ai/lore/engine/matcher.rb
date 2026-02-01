# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Lore
      class Engine < TavernKit::Lore::Engine::Base
        private

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
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

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
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
                data = m[:data].to_s
                if JS_REGEX_MAX_INPUT_BYTES.positive? && data.bytesize > JS_REGEX_MAX_INPUT_BYTES
                  warn_once(
                    warner,
                    warned,
                    [:js_regex_input_too_large, js_re],
                    "JS regex skipped: input too large (bytes=#{data.bytesize}): #{truncate_literal(js_re)}",
                  )
                  next false
                end

                re.match?(data)
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

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
        def strip_macro_comments(text)
          s = text.to_s
          s = s.gsub(/\{\{\/\/(.+?)\}\}/, "")
          s.gsub(/\{\{comment:(.+?)\}\}/, "")
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
        def warn_once(warner, warned, key, message)
          return nil unless warner&.respond_to?(:call)

          if warned.is_a?(Hash)
            return nil if warned[key]

            warned[key] = true
          end

          warner.call(message.to_s)
          nil
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
        def truncate_literal(value, max_len: 200)
          s = value.to_s
          return s if s.length <= max_len

          "#{s[0, max_len]}..."
        rescue StandardError
          ""
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
        def cached_js_regex(value)
          v = value.to_s
          return nil unless v.start_with?("/")

          @js_regex_cache ||= TavernKit::JsRegexCache.new(max_size: JS_REGEX_CACHE_MAX)
          @js_regex_cache.fetch(v)
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
        def normalize_message(message)
          if message.is_a?(Hash)
            h = normalize_hash_keys(message)
            data = h[:data] || h[:content] || h[:text]
            { data: data.to_s }
          else
            { data: message.to_s }
          end
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
        def normalize_recursive_prompt(hash)
          h = normalize_hash_keys(hash)
          data = h[:data] || h[:prompt]
          { data: data.to_s }
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb` (Wave 6 large-file split).
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
      end
    end
  end
end
