# frozen_string_literal: true

module TavernKit
  module Text
    module PatternMatcher
      module_function

      # Match a pattern against text.
      #
      # Patterns can be:
      # - plain strings (substring / whole-word depending on options)
      # - JS-style regex strings: "/pattern/flags" (best-effort flag mapping)
      # - Ruby Regexp objects
      def match?(pattern, text, case_sensitive:, match_whole_words:)
        text = text.to_s

        regex = compile_regex(pattern, case_sensitive: case_sensitive)
        return regex.match?(text) if regex

        needle = pattern.to_s.strip
        return false if needle.empty?

        haystack = case_sensitive ? text : text.downcase
        needle = case_sensitive ? needle : needle.downcase

        return haystack.include?(needle) unless match_whole_words

        words = needle.split(/\s+/)
        return haystack.include?(needle) if words.length > 1

        boundary = "[^A-Za-z0-9_]"
        Regexp.new("(?:^|#{boundary})#{Regexp.escape(needle)}(?:$|#{boundary})").match?(haystack)
      end

      def compile_regex(pattern, case_sensitive:)
        return pattern if pattern.is_a?(Regexp)
        return nil unless pattern.is_a?(String)

        js = parse_js_regex(pattern)
        return nil unless js

        options = 0
        options |= Regexp::IGNORECASE if js[:flags].include?("i") || !case_sensitive
        # JS 's' (dotAll) roughly maps to Ruby's /m (dot matches newline).
        options |= Regexp::MULTILINE if js[:flags].include?("s")

        Regexp.new(js[:source], options)
      rescue RegexpError
        nil
      end

      def parse_js_regex(string)
        return nil unless string.is_a?(String)

        s = string.strip
        return nil unless s.start_with?("/")

        idx = 1
        escaped = false
        while idx < s.length
          ch = s[idx]
          if escaped
            escaped = false
          elsif ch == "\\"
            escaped = true
          elsif ch == "/"
            source = s[1...idx]
            flags = s[(idx + 1)..].to_s
            return nil unless flags.match?(/\A[a-z]*\z/)

            return { source: source, flags: flags }
          end

          idx += 1
        end

        nil
      end
    end
  end
end
