# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Lore
      # Parse ST World Info decorators from entry content.
      #
      # ST v1.15.0 recognizes two decorators when they appear at the very start
      # of the content:
      # - @@activate
      # - @@dont_activate
      #
      # Unknown @@-prefixed lines are treated as normal content (tolerant).
      module DecoratorParser
        module_function

        KNOWN_DECORATORS = %w[@@activate @@dont_activate].freeze

        # @return [Array(String), String] [decorators, content_without_decorators]
        def parse(content)
          s = content.to_s
          return [[], s] unless s.start_with?("@@")

          decorators = []
          lines = s.lines

          idx = 0
          while idx < lines.length
            raw = lines[idx]
            stripped = raw.to_s.strip
            break unless stripped.start_with?("@@")

            decorator =
              if stripped.start_with?("@@@")
                "@@" + stripped.delete_prefix("@@@")
              else
                stripped
              end

            if KNOWN_DECORATORS.any? { |d| decorator.start_with?(d) }
              decorators << decorator
              idx += 1
              next
            end

            break
          end

          [decorators.uniq, lines[idx..]&.join.to_s]
        end
      end
    end
  end
end
