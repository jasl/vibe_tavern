# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      module Tags
        # Base for tags using `name` syntax.
        class NameOnlyTag < Base
          SYNTAX = /\A(#{::Liquid::VariableSignature}+)\s*\z/o

          def initialize(tag_name, markup, parse_context)
            super

            if markup =~ SYNTAX
              @name = Regexp.last_match(1).to_s
            else
              raise ::Liquid::SyntaxError, "Invalid #{tag_name} syntax (expected: #{tag_name} name)"
            end
          end

          private

          attr_reader :name
        end
      end
    end
  end
end
