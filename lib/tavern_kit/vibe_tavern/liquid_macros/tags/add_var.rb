# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        class AddVar < AssignmentTag
          def render_to_output_buffer(context, output)
            store = variables_store(context)
            return output unless store

            key = normalize_key(name)
            rhs = eval_value(context)

            current = store.get(key, scope: :local)
            cur_num = coerce_number(current)
            rhs_num = coerce_number(rhs)

            if !rhs_num.nil? && (current.nil? || !cur_num.nil?)
              store.set(key, (cur_num || 0) + rhs_num, scope: :local)
            else
              store.set(key, "#{current}#{rhs}", scope: :local)
            end

            output
          end
        end
      end
    end
  end
end
