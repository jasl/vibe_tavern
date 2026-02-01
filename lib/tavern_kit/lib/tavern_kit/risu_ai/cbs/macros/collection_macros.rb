# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_dictelement(args)
          dict = parse_dict(args[0])
          key = args[1].to_s

          element =
            case dict
            when Hash
              dict[key]
            when Array
              idx = Integer(key, exception: false)
              idx ? dict[idx] : nil
            else
              nil
            end

          element = "null" if element.nil?
          element.is_a?(Hash) || element.is_a?(Array) ? ::JSON.generate(element) : element.to_s
        end
        private_class_method :resolve_dictelement

        def resolve_objectassert(args)
          dict = parse_object(args[0])
          key = args[1].to_s

          dict[key] = args[2].to_s unless js_truthy?(dict[key])

          ::JSON.generate(dict)
        end
        private_class_method :resolve_objectassert

        def resolve_element(args)
          return args[0].to_s if args.length < 2

          current = args[0].to_s

          args.drop(1).each do |key|
            return "null" unless current.is_a?(String)

            parsed = ::JSON.parse(current)
            return "null" unless parsed.is_a?(Hash) || parsed.is_a?(Array)

            current =
              case parsed
              when Hash
                parsed[key.to_s]
              when Array
                idx = Integer(key.to_s, exception: false)
                idx ? parsed[idx] : nil
              end

            return "null" unless js_truthy?(current)
          end

          if current.is_a?(Hash) || current.is_a?(Array)
            ::JSON.generate(current)
          else
            current.to_s
          end
        rescue ::JSON::ParserError
          "null"
        end
        private_class_method :resolve_element

        def resolve_arrayshift(args)
          arr = parse_cbs_array(args[0])
          arr.shift
          make_array(arr)
        end
        private_class_method :resolve_arrayshift

        def resolve_arraypop(args)
          arr = parse_cbs_array(args[0])
          arr.pop
          make_array(arr)
        end
        private_class_method :resolve_arraypop

        def resolve_arraypush(args)
          arr = parse_cbs_array(args[0])
          arr << args[1].to_s
          make_array(arr)
        end
        private_class_method :resolve_arraypush

        def resolve_arraysplice(args)
          arr = parse_cbs_array(args[0])
          start = js_number(args[1])
          delete_count = js_number(args[2])

          return make_array(arr) if start.nan? || delete_count.nan?

          start_idx = start.to_i
          delete_n = delete_count.to_i

          arr.slice!(start_idx, delete_n)
          arr.insert(start_idx, args[3].to_s)

          make_array(arr)
        end
        private_class_method :resolve_arraysplice

        def resolve_arrayassert(args)
          arr = parse_cbs_array(args[0])
          index = js_number(args[1])
          return make_array(arr) if index.nan?

          idx = index.to_i
          if idx >= arr.length
            arr[idx] = args[2].to_s
          end

          make_array(arr)
        end
        private_class_method :resolve_arrayassert

        def resolve_makearray(args)
          make_array(args)
        end
        private_class_method :resolve_makearray

        def resolve_makedict(args)
          out = {}

          Array(args).each do |raw|
            s = raw.to_s
            first_equal = s.index("=")
            next unless first_equal

            key = s[0...first_equal]
            value = s[(first_equal + 1)..]
            out[key] = value.nil? ? "null" : value
          end

          ::JSON.generate(out)
        end
        private_class_method :resolve_makedict

        def resolve_range(args)
          arr = parse_cbs_array(args[0])

          start = arr.length > 1 ? js_number(arr[0]) : 0.0
          end_num = arr.length > 1 ? js_number(arr[1]) : js_number(arr[0])
          step = arr.length > 2 ? js_number(arr[2]) : 1.0

          return make_array([]) if start.nan? || end_num.nan? || step.nan?
          return make_array([]) if step <= 0

          out = []
          i = start

          # Guardrail: prevent pathological loops from user input.
          10_000.times do
            break unless i < end_num

            out << format_number(i)
            i += step
          end

          make_array(out)
        end
        private_class_method :resolve_range

        def resolve_filter(args)
          array = parse_cbs_array(args[0])
          filter_type = args[1].to_s
          filter_type = "all" unless %w[all nonempty unique].include?(filter_type)

          filtered =
            case filter_type
            when "all"
              array.each_with_index.filter_map do |v, i|
                next nil if v == ""

                first = js_index_of(array, v)
                first == i ? v : nil
              end
            when "nonempty"
              array.reject { |v| v == "" }
            when "unique"
              array.each_with_index.filter_map do |v, i|
                first = js_index_of(array, v)
                first == i ? v : nil
              end
            end

          make_array(filtered)
        end
        private_class_method :resolve_filter

        def parse_dict(value)
          parsed = ::JSON.parse(value.to_s)
          parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : {}
        rescue ::JSON::ParserError
          {}
        end
        private_class_method :parse_dict

        def parse_object(value)
          parsed = ::JSON.parse(value.to_s)
          parsed.is_a?(Hash) ? parsed : {}
        rescue ::JSON::ParserError
          {}
        end
        private_class_method :parse_object

        def js_truthy?(value)
          return false if value.nil? || value == false

          case value
          when String
            !value.empty?
          when Numeric
            value != 0 && !(value.respond_to?(:nan?) && value.nan?)
          else
            true
          end
        end
        private_class_method :js_truthy?

        def js_index_of(array, element)
          array.each_with_index do |v, i|
            if js_strict_equal?(v, element)
              return i
            end
          end

          nil
        end
        private_class_method :js_index_of

        def js_strict_equal?(a, b)
          # Approximation of JS `===` for primitives and reference equality for objects.
          if a.is_a?(Numeric) && b.is_a?(Numeric)
            return a == b
          end

          if a.is_a?(String) && b.is_a?(String)
            return a == b
          end

          if (a == true || a == false) && (b == true || b == false)
            return a == b
          end

          if a.nil? && b.nil?
            return true
          end

          # Objects/arrays/hashes: reference equality.
          a.equal?(b)
        end
        private_class_method :js_strict_equal?
      end
    end
  end
end
