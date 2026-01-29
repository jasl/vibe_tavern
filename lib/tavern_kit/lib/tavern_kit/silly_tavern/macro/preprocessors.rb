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

          str = rewrite_legacy_markers(str, environment: environment)
          str = normalize_time_utc_legacy_syntax(str)
          cleanup_trim(str)
        end

        # ST legacy "angle bracket" markers are commonly used in prompt strings.
        # They must be normalized before `{{...}}` macro expansion.
        def self.rewrite_legacy_markers(text, environment:)
          user = environment.respond_to?(:user_name) ? environment.user_name.to_s : ""
          char = environment.respond_to?(:character_name) ? environment.character_name.to_s : ""
          group = environment.respond_to?(:group_name) ? environment.group_name.to_s : ""

          text
            .gsub(/<USER>/i, user)
            .gsub(/<BOT>/i, char)
            .gsub(/<CHAR>/i, char)
            .gsub(/<CHARIFNOTGROUP>/i, group)
            .gsub(/<GROUP>/i, group)
        end

        # Normalize `{{time_UTC-10}}` -> `{{time_UTC::-10}}` so parsers only have to
        # support a single argument style.
        def self.normalize_time_utc_legacy_syntax(text)
          text.gsub(/\{\{time_UTC([+-]\d+)\}\}/i) do
            "{{time_UTC::#{Regexp.last_match(1)}}}"
          end
        end

        # `{{trim}}` is a whitespace control marker. It removes surrounding
        # newlines and itself.
        def self.cleanup_trim(text)
          text.gsub(/(?:\r?\n)*\{\{trim\}\}(?:\r?\n)*/i, "")
        end
      end
    end
  end
end
