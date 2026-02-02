# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        # Shared helpers for VariablesStore-mutating Liquid tags.
        class Base < ::Liquid::Tag
          def blank?
            true
          end

          private

          def variables_store(context)
            store = context.registers[:variables_store]
            return store if store.respond_to?(:get) &&
              store.respond_to?(:set) &&
              store.respond_to?(:has?) &&
              store.respond_to?(:delete) &&
              store.respond_to?(:add)

            nil
          end

          def normalize_key(key)
            key.to_s
          end

          def coerce_number(value)
            return value if value.is_a?(Numeric)

            s = value.to_s.strip
            return nil if s.empty?

            if s.match?(/\A[-+]?\d+\z/)
              Integer(s, 10)
            else
              Float(s)
            end
          rescue ArgumentError, TypeError
            nil
          end
        end
      end
    end
  end
end
