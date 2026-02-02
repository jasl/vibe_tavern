# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      # Internal helper methods for `V2Engine`.
      #
      # Pure refactor: extracted from `silly_tavern/macro/v2_engine.rb`.
      class V2Engine < TavernKit::Macro::Engine::Base
        private

        def normalize_value_type(value)
          case value
          when Symbol
            value.to_s.downcase.to_sym
          else
            value.to_s.strip.downcase.to_sym
          end
        rescue StandardError
          :string
        end

        def value_of_type?(value, type)
          trimmed = value.to_s.strip

          case type
          when :string
            true
          when :integer
            trimmed.match?(/\A-?\d+\z/)
          when :number
            n = Float(trimmed)
            n.finite?
          when :boolean
            v = trimmed.downcase
            TavernKit::Coerce::TRUE_STRINGS.include?(v) || TavernKit::Coerce::FALSE_STRINGS.include?(v)
          else
            false
          end
        rescue ArgumentError, TypeError
          false
        end

        def trim_scoped_content(text, trim_indent: true)
          s = text.to_s
          return "" if s.empty?

          normalized = s.gsub("\r\n", "\n")
          stripped = normalized.strip
          return "" if stripped.empty?

          return stripped unless trim_indent == true

          lines = stripped.split("\n", -1)
          indents =
            lines.filter_map do |line|
              next nil if line.strip.empty?

              line[/\A[ \t]*/].to_s.length
            end

          min_indent = indents.min || 0
          return stripped if min_indent.zero?

          lines.map { |line| line.start_with?(" " * min_indent) ? line[min_indent..] : line }.join("\n")
        end

        def lookup_dynamic(hash, key)
          return hash[key] if hash.key?(key)
          return hash[key.to_s] if hash.key?(key.to_s)
          return hash[key.to_sym] if hash.key?(key.to_sym)

          down = key.to_s.downcase
          return hash[down] if hash.key?(down)

          nil
        end

        def whitespace?(byte)
          byte == 32 || byte == 9 || byte == 10 || byte == 13
        end

        def flag_byte?(byte)
          case byte
          when "!".ord, "?".ord, "~".ord, ">".ord, "/".ord, "#".ord then true
          else false
          end
        end

        def normalize_value(value)
          case value
          when Numeric
            return value.to_s if value.is_a?(Integer)

            f = value.to_f
            return f.to_i.to_s if f.finite? && (f % 1).zero?

            f.to_s
          when nil then ""
          when TrueClass then "true"
          when FalseClass then "false"
          else value.to_s
          end
        rescue StandardError
          ""
        end

        def build_original_once(env)
          return nil unless env.respond_to?(:original)

          original = env.original
          return nil if original.nil? || original.to_s.empty?

          used = false
          lambda do
            return "" if used

            used = true
            original.to_s
          end
        end

        def remove_unresolved_placeholders(str)
          s = str.to_s
          return s if s.empty?

          prev = nil
          cur = s
          5.times do
            break if cur == prev

            prev = cur
            cur = cur.gsub(/\{\{[^{}]*\}\}/, "")
          end

          cur
        end
      end
    end
  end
end
