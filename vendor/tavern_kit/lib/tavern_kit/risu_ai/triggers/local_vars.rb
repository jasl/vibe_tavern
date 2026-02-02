# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Triggers
      # Per-trigger local variable storage keyed by "indent" scope.
      #
      # Pure refactor: extracted from `risu_ai/triggers.rb`.
      class LocalVars
        def initialize
          @by_indent = {}
        end

        def get(key, current_indent:)
          i = current_indent.to_i
          while i >= 0
            scope = @by_indent[i]
            return scope[key] if scope && scope.key?(key)

            i -= 1
          end

          nil
        end

        def set(key, value, indent:)
          final_value = value.nil? ? "null" : value.to_s

          found_indent = nil
          i = indent.to_i
          while i >= 0
            scope = @by_indent[i]
            if scope && scope.key?(key)
              found_indent = i
              break
            end
            i -= 1
          end

          target_indent = found_indent || indent.to_i
          (@by_indent[target_indent] ||= {})[key] = final_value
        end

        def clear_at_indent(indent)
          threshold = indent.to_i
          @by_indent.keys.each do |i|
            @by_indent.delete(i) if i >= threshold
          end
        end
      end
    end
  end
end
