# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        class AddGlobal < AssignmentTag
          def render_to_output_buffer(context, output)
            store = variables_store(context)
            return output unless store

            key = normalize_key(name)
            rhs = eval_value(context)

            current = store.get(key, scope: :global)
            cur_num = coerce_number(current)
            rhs_num = coerce_number(rhs)

            if !rhs_num.nil? && (current.nil? || !cur_num.nil?)
              store.set(key, (cur_num || 0) + rhs_num, scope: :global)
            else
              store.set(key, "#{current}#{rhs}", scope: :global)
            end

            output
          end
        end
      end
    end
  end
end
