# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_startswith(args)
          args[0].to_s.start_with?(args[1].to_s) ? "1" : "0"
        end
        private_class_method :resolve_startswith

        def resolve_endswith(args)
          args[0].to_s.end_with?(args[1].to_s) ? "1" : "0"
        end
        private_class_method :resolve_endswith

        def resolve_contains(args)
          args[0].to_s.include?(args[1].to_s) ? "1" : "0"
        end
        private_class_method :resolve_contains

        def resolve_replace(args)
          args[0].to_s.gsub(args[1].to_s, args[2].to_s)
        end
        private_class_method :resolve_replace

        def resolve_split(args)
          delimiter = args[1].to_s
          make_array(args[0].to_s.split(delimiter))
        end
        private_class_method :resolve_split

        def resolve_join(args)
          list = parse_cbs_array(args[0])
          delimiter = args[1].to_s
          list.map { |v| v.is_a?(String) ? v : ::JSON.generate(v) }.join(delimiter)
        end
        private_class_method :resolve_join

        def resolve_spread(args)
          list = parse_cbs_array(args[0])
          list.map { |v| v.is_a?(String) ? v : ::JSON.generate(v) }.join("::")
        end
        private_class_method :resolve_spread

        def resolve_trim(args)
          args[0].to_s.strip
        end
        private_class_method :resolve_trim

        def resolve_length(args)
          args[0].to_s.length.to_s
        end
        private_class_method :resolve_length

        def resolve_lower(args)
          args[0].to_s.downcase
        end
        private_class_method :resolve_lower

        def resolve_upper(args)
          args[0].to_s.upcase
        end
        private_class_method :resolve_upper

        def resolve_capitalize(args)
          s = args[0].to_s
          return "" if s.empty?

          s[0].upcase + s[1..].to_s
        end
        private_class_method :resolve_capitalize
      end
    end
  end
end
