# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      # Preprocessors normalize legacy syntax before the main macro expansion.
      #
      # This module is intentionally conservative: if an input doesn't match a
      # known rewrite rule, it is returned unchanged (tolerant external input).
      module Preprocessors
        def self.preprocess(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          str = normalize_time_utc_legacy_syntax(str)
          rewrite_legacy_markers(str)
        end

        def self.postprocess(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          str = unescape_braces(str)
          str = cleanup_trim(str)
          cleanup_else_marker(str)
        end

        # Legacy "angle bracket" markers are commonly used in prompt strings.
        #
        # They are rewritten into their equivalent macro forms so the normal
        # engine pipeline resolves them (and custom handlers can intercept).
        def self.rewrite_legacy_markers(text)
          text
            .gsub(/<USER>/i, "{{user}}")
            .gsub(/<BOT>/i, "{{char}}")
            .gsub(/<CHAR>/i, "{{char}}")
            .gsub(/<GROUP>/i, "{{group}}")
            .gsub(/<CHARIFNOTGROUP>/i, "{{charIfNotGroup}}")
        end

        # Normalize `{{time_UTC-10}}` -> `{{time::UTC-10}}` so parsers only have to
        # support a single canonical form.
        def self.normalize_time_utc_legacy_syntax(text)
          text.gsub(/\{\{time_(UTC[+-]\d+)\}\}/i) do
            "{{time::#{Regexp.last_match(1)}}}"
          end
        end

        ELSE_MARKER = "\u0000\u001FELSE\u001F\u0000"

        # Unescape braces: `\{` → `{` and `\}` → `}`.
        def self.unescape_braces(text)
          text.gsub(/\\([{}])/, "\\1")
        end

        # Legacy `{{trim}}` behavior removes itself and surrounding newlines in
        # post-processing.
        def self.cleanup_trim(text)
          text.gsub(/(?:\r?\n)*\{\{trim\}\}(?:\r?\n)*/i, "")
        end

        def self.cleanup_else_marker(text)
          text.gsub(ELSE_MARKER, "")
        end
      end
    end
  end
end
