# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        class IncGlobal < NameOnlyTag
          def render_to_output_buffer(context, output)
            store = variables_store(context)
            return output unless store

            key = normalize_key(name)
            current = store.get(key, scope: :global)
            cur_num = coerce_number(current) || 0
            store.set(key, cur_num + 1, scope: :global)
            output
          end
        end
      end
    end
  end
end
