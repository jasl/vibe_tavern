# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        class SetDefaultVar < AssignmentTag
          def render_to_output_buffer(context, output)
            store = variables_store(context)
            return output unless store

            key = normalize_key(name)
            store.set(key, eval_value(context), scope: :local) unless store.has?(key, scope: :local)
            output
          end
        end
      end
    end
  end
end
