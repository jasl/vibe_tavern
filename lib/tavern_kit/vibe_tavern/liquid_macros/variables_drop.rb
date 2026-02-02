# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      # Exposes VariablesStore reads as natural Liquid access:
      # - {{ var.mood }}
      # - {{ global.score }}
      # - {{ var["some-key"] }}
      class VariablesDrop < ::Liquid::Drop
        def initialize(store, scope:)
          super()
          @store = store
          @scope = scope
        end

        def liquid_method_missing(method)
          key = method.to_s
          return nil if key.empty?

          if @store.respond_to?(:has?) && @store.has?(key, scope: @scope)
            @store.get(key, scope: @scope)
          elsif @context&.strict_variables
            raise ::Liquid::UndefinedDropMethod, "undefined method #{method}"
          else
            nil
          end
        end
      end
    end
  end
end
