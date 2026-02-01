# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      class Engine < TavernKit::Lore::Engine::Base
        # Scan buffer builder + matching helpers (ST-like).
        #
        # Pure refactor: extracted from `silly_tavern/lore/engine.rb` (Wave 6 large-file split).
        class Buffer
          JS_REGEX_CACHE_MAX = 512

          def initialize(messages:, default_depth:, scan_context:, scan_injects:)
            @depth_buffer = Array(messages).first(MAX_SCAN_DEPTH).map { |m| m.to_s.strip }
            @default_depth = default_depth.to_i
            @skew = 0

            @scan_context = scan_context.is_a?(Hash) ? scan_context : {}
            @scan_injects = Array(scan_injects).map(&:to_s).map(&:strip).reject(&:empty?)

            @recurse_buffer = +""
          end

          def depth
            @default_depth + @skew
          end

          def advance_scan
            @skew += 1
          end

          def add_recurse(text)
            s = text.to_s
            return if s.strip.empty?

            @recurse_buffer << "\n" unless @recurse_buffer.empty?
            @recurse_buffer << s
            truncate_recurse_buffer!
          end

          def has_recurse?
            !@recurse_buffer.empty?
          end

          def get(ext, scan_state)
            entry_depth = ext.scan_depth
            depth = entry_depth.nil? ? self.depth : entry_depth.to_i
            return "" if depth <= 0

            depth = [depth, @depth_buffer.length].min
            base_lines = @depth_buffer.first(depth).reject(&:empty?)

            result = MATCHER + base_lines.join(JOINER)

            result = append_scan_context(result, ext)
            result = append_injects(result)

            if scan_state != :min_activations && !@recurse_buffer.strip.empty?
              result = [result, @recurse_buffer].join(JOINER)
            end

            result
          end

          def score(scan_entry, scan_state, case_sensitive:, match_whole_words:)
            scan_text = get(scan_entry.ext, scan_state)
            return 0 if scan_text.empty?

            scan_text_downcase = case_sensitive ? nil : scan_text.downcase

            primary = Array(scan_entry.entry.keys)
            secondary = Array(scan_entry.entry.secondary_keys)

            primary_score =
              primary.count do |k|
                Buffer.match_pre_normalized?(
                  scan_text,
                  scan_text_downcase,
                  k,
                  scan_entry,
                  case_sensitive: case_sensitive,
                  match_whole_words: match_whole_words,
                )
              end
            return 0 if primary.empty?

            secondary_score =
              secondary.count do |k|
                Buffer.match_pre_normalized?(
                  scan_text,
                  scan_text_downcase,
                  k,
                  scan_entry,
                  case_sensitive: case_sensitive,
                  match_whole_words: match_whole_words,
                )
              end

            # Only positive logic influences group scoring (ST parity).
            return primary_score if secondary.empty?

            case scan_entry.ext.selective_logic
            when :and_any
              primary_score + secondary_score
            when :and_all
              secondary_score == secondary.length ? (primary_score + secondary_score) : primary_score
            else
              primary_score
            end
          end

          def self.match?(haystack, needle, scan_entry, case_sensitive:, match_whole_words:)
            match_pre_normalized?(haystack, nil, needle, scan_entry, case_sensitive: case_sensitive, match_whole_words: match_whole_words)
          end

          def self.match_pre_normalized?(haystack, haystack_downcase, needle, _scan_entry, case_sensitive:, match_whole_words:)
            h = haystack.to_s
            n = needle.to_s.strip
            return false if n.empty?

            regex = cached_js_regex(n)
            return regex.match?(h) if regex

            if case_sensitive
              hay = h
              nee = n
            else
              hay = haystack_downcase || h.downcase
              nee = n.downcase
            end

            if match_whole_words
              parts = nee.split(/\s+/)
              if parts.length > 1
                hay.include?(nee)
              else
                /(?:^|\\W)#{Regexp.escape(nee)}(?:$|\\W)/.match?(hay)
              end
            else
              hay.include?(nee)
            end
          end

          def self.cached_js_regex(value)
            v = value.to_s
            return nil unless v.start_with?("/")

            @js_regex_cache ||= TavernKit::JsRegexCache.new(max_size: JS_REGEX_CACHE_MAX)
            @js_regex_cache.fetch(v)
          end
          private_class_method :cached_js_regex

          private

          def append_scan_context(base, ext)
            parts = []

            parts << @scan_context[:persona_description] if ext.match_persona_description?
            parts << @scan_context[:character_description] if ext.match_character_description?
            parts << @scan_context[:character_personality] if ext.match_character_personality?
            parts << @scan_context[:character_depth_prompt] if ext.match_character_depth_prompt?
            parts << @scan_context[:scenario] if ext.match_scenario?
            parts << @scan_context[:creator_notes] if ext.match_creator_notes?

            parts = parts.compact.map(&:to_s).map(&:strip).reject(&:empty?)
            return base if parts.empty?

            [base, parts.join(JOINER)].join(JOINER)
          end

          def append_injects(base)
            return base if @scan_injects.empty?

            [base, @scan_injects.join(JOINER)].join(JOINER)
          end

          def truncate_recurse_buffer!
            return if @recurse_buffer.bytesize <= MAX_RECURSE_BUFFER_BYTES

            tail = @recurse_buffer.byteslice(-MAX_RECURSE_BUFFER_BYTES, MAX_RECURSE_BUFFER_BYTES) || +""
            tail = tail.scrub("")
            @recurse_buffer.replace(tail)
          end
        end
      end
    end
  end
end
