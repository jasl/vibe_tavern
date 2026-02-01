# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_min(args)
          list = aggregate_values(args)
          return "Infinity" if list.empty?

          nums = list.map { |v| js_number_or_zero(v) }
          format_number(nums.min)
        rescue StandardError
          "Infinity"
        end
        private_class_method :resolve_min

        def resolve_max(args)
          list = aggregate_values(args)
          return "-Infinity" if list.empty?

          nums = list.map { |v| js_number_or_zero(v) }
          format_number(nums.max)
        rescue StandardError
          "-Infinity"
        end
        private_class_method :resolve_max

        def resolve_sum(args)
          list = aggregate_values(args)
          nums = list.map { |v| js_number_or_zero(v) }
          format_number(nums.sum(0.0))
        rescue StandardError
          "0"
        end
        private_class_method :resolve_sum

        def resolve_average(args)
          list = aggregate_values(args)
          nums = list.map { |v| js_number_or_zero(v) }
          sum = nums.sum(0.0)
          avg = sum / nums.length
          format_number(avg)
        rescue StandardError
          "NaN"
        end
        private_class_method :resolve_average

        def resolve_fixnum(args)
          num = js_number(args[0])
          return num.to_s if num.infinite?
          return "NaN" if num.nan?

          digits_raw = args[1].to_s
          digits =
            if digits_raw.empty?
              0
            else
              d = js_number(digits_raw)
              (d.nan? || d.infinite?) ? 0 : d.to_i
            end

          return "NaN" if digits.negative? || digits > 100

          format("%.#{digits}f", num)
        rescue StandardError
          "NaN"
        end
        private_class_method :resolve_fixnum

        def aggregate_values(args)
          return [] if args.empty?
          return args if args.length > 1

          parse_cbs_array(args[0])
        end
        private_class_method :aggregate_values

        def js_number_or_zero(value)
          n = js_number(value)
          n.nan? ? 0.0 : n
        end
        private_class_method :js_number_or_zero
      end
    end
  end
end
