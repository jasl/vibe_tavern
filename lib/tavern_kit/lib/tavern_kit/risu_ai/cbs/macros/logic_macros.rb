# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_equal(args)
          args[0].to_s == args[1].to_s ? "1" : "0"
        end
        private_class_method :resolve_equal

        def resolve_notequal(args)
          args[0].to_s != args[1].to_s ? "1" : "0"
        end
        private_class_method :resolve_notequal

        def resolve_greater(args)
          js_number(args[0]) > js_number(args[1]) ? "1" : "0"
        end
        private_class_method :resolve_greater

        def resolve_less(args)
          js_number(args[0]) < js_number(args[1]) ? "1" : "0"
        end
        private_class_method :resolve_less

        def resolve_greaterequal(args)
          js_number(args[0]) >= js_number(args[1]) ? "1" : "0"
        end
        private_class_method :resolve_greaterequal

        def resolve_lessequal(args)
          js_number(args[0]) <= js_number(args[1]) ? "1" : "0"
        end
        private_class_method :resolve_lessequal

        def resolve_and(args)
          args[0].to_s == "1" && args[1].to_s == "1" ? "1" : "0"
        end
        private_class_method :resolve_and

        def resolve_or(args)
          args[0].to_s == "1" || args[1].to_s == "1" ? "1" : "0"
        end
        private_class_method :resolve_or

        def resolve_not(args)
          args[0].to_s == "1" ? "0" : "1"
        end
        private_class_method :resolve_not

        def resolve_all(args)
          array = args.length > 1 ? args : parse_json_array(args[0])
          array.all? { |v| v.to_s == "1" } ? "1" : "0"
        end
        private_class_method :resolve_all

        def resolve_any(args)
          array = args.length > 1 ? args : parse_json_array(args[0])
          array.any? { |v| v.to_s == "1" } ? "1" : "0"
        end
        private_class_method :resolve_any

        def parse_json_array(value)
          s = value.to_s

          arr = ::JSON.parse(s)
          arr.is_a?(Array) ? arr : s.split("§")
        rescue ::JSON::ParserError
          s.split("§")
        end
        private_class_method :parse_json_array
      end
    end
  end
end
