# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Triggers
      module_function

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def numeric_equal?(a, b)
        na = safe_float(a)
        nb = safe_float(b)
        return a.to_s == b.to_s if na.nan? || nb.nan?

        na == nb
      end

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def approx_equal?(a, b)
        na = safe_float(a)
        nb = safe_float(b)

        if na.nan? || nb.nan?
          normalize = ->(v) { v.to_s.downcase.delete(" ") }
          return normalize.call(a) == normalize.call(b)
        end

        (na - nb).abs < 0.0001
      end

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def numeric_compare?(a, b, op)
        na = safe_float(a)
        nb = safe_float(b)
        return false if na.nan? || nb.nan?

        na.public_send(op, nb)
      end

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def safe_float(value)
        s = value.to_s.strip
        return Float::NAN if s == "NaN"
        return Float::INFINITY if s == "Infinity"
        return -Float::INFINITY if s == "-Infinity"

        Float(s)
      rescue ArgumentError, TypeError
        Float::NAN
      end

      # JS Array#slice index conversion (ToIntegerOrInfinity + bounds clamp).
      #
      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def js_slice_index(value, len)
        num = value.is_a?(Numeric) ? value.to_f : safe_float(value)
        inf = num.infinite?
        idx = inf ? (inf.positive? ? len : 0) : num.truncate

        if idx.negative?
          idx += len
          idx = 0 if idx.negative?
        elsif idx > len
          idx = len
        end

        idx
      end

      # Format a Float like JS `Number(...).toString()`:
      # - integer numbers render without ".0"
      # - NaN/Infinity render as their identifier strings
      #
      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def format_js_number(value)
        num = value.is_a?(Numeric) ? value.to_f : safe_float(value)
        return "NaN" if num.nan?

        inf = num.infinite?
        return inf.positive? ? "Infinity" : "-Infinity" if inf

        (num % 1).zero? ? num.to_i.to_s : num.to_s
      end

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def parse_js_float_prefix(value)
        s = value.to_s.lstrip
        return Float::NAN if s.empty?

        return Float::INFINITY if s.start_with?("Infinity")
        return -Float::INFINITY if s.start_with?("-Infinity")
        return Float::NAN if s.start_with?("NaN")

        m = s.match(/\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/)
        return Float::NAN unless m

        safe_float(m[0])
      end
      private_class_method :parse_js_float_prefix

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def v2_calc_string(expr)
        tokens = v2_calc_tokenize(expr)
        rpn = v2_calc_to_rpn(tokens)
        v2_calc_eval_rpn(rpn)
      end
      private_class_method :v2_calc_string

      def v2_calc_tokenize(expr)
        s = expr.to_s.gsub(/\s+/, "")
        tokens = []

        i = 0
        while i < s.length
          ch = s[i]

          if ch == "(" || ch == ")"
            tokens << ch
            i += 1
            next
          end

          if "+-*/%^".include?(ch)
            if ch == "-" && (tokens.empty? || tokens.last.is_a?(String) && tokens.last != ")")
              # Unary minus becomes part of the number token.
              j = i + 1
              j += 1 while j < s.length && s[j] =~ /[0-9.]/
              if j < s.length && s[j] =~ /[eE]/
                k = j + 1
                k += 1 if k < s.length && s[k] =~ /[+-]/
                k += 1 while k < s.length && s[k] =~ /\d/
                j = k
              end

              tokens << safe_float(s[i...j])
              i = j
            else
              tokens << ch
              i += 1
            end
            next
          end

          if ch =~ /[0-9.]/
            j = i
            j += 1 while j < s.length && s[j] =~ /[0-9.]/
            if j < s.length && s[j] =~ /[eE]/
              k = j + 1
              k += 1 if k < s.length && s[k] =~ /[+-]/
              k += 1 while k < s.length && s[k] =~ /\d/
              j = k
            end

            tokens << safe_float(s[i...j])
            i = j
            next
          end

          raise ArgumentError, "Unexpected token: #{ch}"
        end

        tokens
      end
      private_class_method :v2_calc_tokenize

      def v2_calc_to_rpn(tokens)
        prec = { "+" => 2, "-" => 2, "*" => 3, "/" => 3, "%" => 3, "^" => 4 }.freeze

        out = []
        ops = []

        tokens.each do |t|
          if t.is_a?(Numeric)
            out << t
            next
          end

          if t == "("
            ops << t
            next
          end

          if t == ")"
            out << ops.pop while ops.any? && ops.last != "("
            ops.pop if ops.last == "("
            next
          end

          # operator
          while ops.any? && ops.last != "(" && prec.fetch(ops.last) >= prec.fetch(t)
            out << ops.pop
          end
          ops << t
        end

        out.concat(ops.reverse.reject { |op| op == "(" })
        out
      end
      private_class_method :v2_calc_to_rpn

      def v2_calc_eval_rpn(rpn)
        stack = []

        rpn.each do |t|
          if t.is_a?(Numeric)
            stack << t
            next
          end

          b = stack.pop || Float::NAN
          a = stack.pop || Float::NAN

          stack <<
            case t
            when "+"
              a + b
            when "-"
              a - b
            when "*"
              a * b
            when "/"
              a / b
            when "%"
              b.zero? ? Float::NAN : (a % b)
            when "^"
              a**b
            else
              Float::NAN
            end
        end

        stack.pop || 0.0
      rescue ZeroDivisionError, FloatDomainError
        Float::NAN
      end
      private_class_method :v2_calc_eval_rpn

      # Pure refactor: extracted from `risu_ai/triggers/helpers.rb`.
      def equivalent?(a, b)
        tv = b.to_s
        sv = a.to_s

        if tv == "true"
          sv == "true" || sv == "1"
        elsif tv == "false"
          !(sv == "true" || sv == "1")
        else
          sv == tv
        end
      end
    end
  end
end
