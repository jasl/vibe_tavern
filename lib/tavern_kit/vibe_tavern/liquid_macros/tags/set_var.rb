# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        class SetVar < AssignmentTag
          def render_to_output_buffer(context, output)
            store = variables_store(context)
            return output unless store

            store.set(normalize_key(name), eval_value(context), scope: :local)
            output
          end
        end
      end
    end
  end
end
