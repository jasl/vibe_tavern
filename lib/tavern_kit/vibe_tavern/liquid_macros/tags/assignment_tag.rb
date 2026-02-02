# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        # Base for tags using `name = expression` syntax.
        class AssignmentTag < Base
          SYNTAX = /(#{::Liquid::VariableSignature}+)\s*=\s*(.*)\s*/om

          def initialize(tag_name, markup, parse_context)
            super

            if markup =~ SYNTAX
              @name = Regexp.last_match(1).to_s
              @expr = ::Liquid::Variable.new(Regexp.last_match(2), parse_context)
            else
              raise ::Liquid::SyntaxError, "Invalid #{tag_name} syntax (expected: #{tag_name} name = value)"
            end
          end

          private

          attr_reader :name, :expr

          def eval_value(context)
            expr.render(context)
          end
        end
      end
    end
  end
end
