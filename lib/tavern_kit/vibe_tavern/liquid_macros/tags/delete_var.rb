# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        class DeleteVar < NameOnlyTag
          def render_to_output_buffer(context, output)
            store = variables_store(context)
            return output unless store

            store.delete(normalize_key(name), scope: :local)
            output
          end
        end
      end
    end
  end
end
