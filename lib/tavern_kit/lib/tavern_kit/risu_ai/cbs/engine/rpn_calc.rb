# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Internal RPN evaluator used by `{{calc::...}}`.
      #
      # Pure refactor: extracted from `risu_ai/cbs/engine.rb`.
      class Engine < TavernKit::Macro::Engine::Base
        private

        def execute_rpn_calc(text, environment:)
          expr = text.to_s.dup

          expr = expr
            .gsub(/\$([a-zA-Z0-9_]+)/) { |m| number_or_zero(chat_var(environment, Regexp.last_match(1))) }
            .gsub(/\@([a-zA-Z0-9_]+)/) { |m| number_or_zero(global_var(environment, Regexp.last_match(1))) }
            .gsub("&&", "&")
            .gsub("||", "|")
            .gsub("<=", "≤")
            .gsub(">=", "≥")
            .gsub("==", "=")
            .gsub("!=", "≠")
            .gsub(/null/i, "0")

          rpn = to_rpn(expr)
          eval_rpn(rpn)
        end

        def to_rpn(expr)
          operators = {
            "+" => { precedence: 2, assoc: :left },
            "-" => { precedence: 2, assoc: :left },
            "*" => { precedence: 3, assoc: :left },
            "/" => { precedence: 3, assoc: :left },
            "^" => { precedence: 4, assoc: :left },
            "%" => { precedence: 3, assoc: :left },
            "<" => { precedence: 1, assoc: :left },
            ">" => { precedence: 1, assoc: :left },
            "|" => { precedence: 1, assoc: :left },
            "&" => { precedence: 1, assoc: :left },
            "≤" => { precedence: 1, assoc: :left },
            "≥" => { precedence: 1, assoc: :left },
            "=" => { precedence: 1, assoc: :left },
            "≠" => { precedence: 1, assoc: :left },
            "!" => { precedence: 5, assoc: :right },
          }

          keys = operators.keys
          s = expr.to_s.gsub(/\s+/, "")

          tokens = []
          last = +""

          s.each_char.with_index do |ch, idx|
            if ch == "-" && (idx == 0 || keys.include?(s[idx - 1]) || s[idx - 1] == "(")
              last << ch
              next
            end

            if keys.include?(ch)
              tokens << (last.empty? ? "0" : last)
              last = +""
              tokens << ch
              next
            end

            last << ch
          end

          tokens << (last.empty? ? "0" : last)

          output = []
          stack = []

          tokens.each do |tok|
            if number_literal?(tok)
              output << tok
              next
            end

            next unless keys.include?(tok)

            while stack.any?
              top = stack[-1]
              break unless keys.include?(top)

              if (operators[tok][:assoc] == :left && operators[tok][:precedence] <= operators[top][:precedence]) ||
                 (operators[tok][:assoc] == :right && operators[tok][:precedence] < operators[top][:precedence])
                output << stack.pop
              else
                break
              end
            end

            stack << tok
          end

          output.concat(stack.reverse)
        end

        def eval_rpn(tokens)
          stack = []

          tokens.each do |tok|
            if number_literal?(tok)
              stack << tok.to_f
              next
            end

            b = stack.pop.to_f
            a = stack.pop.to_f

            stack <<
              case tok
              when "+" then a + b
              when "-" then a - b
              when "*" then a * b
              when "/" then a / b
              when "^" then a**b
              when "%" then a % b
              when "<" then a < b ? 1 : 0
              when ">" then a > b ? 1 : 0
              when "≤" then a <= b ? 1 : 0
              when "≥" then a >= b ? 1 : 0
              when "=" then a == b ? 1 : 0
              when "≠" then a != b ? 1 : 0
              when "!" then b != 0 ? 0 : 1
              when "|" then a != 0 ? a : b
              when "&" then a != 0 ? b : a
              else
                0
              end
          end

          stack.empty? ? 0 : stack.pop
        end

        def number_literal?(token)
          t = token.to_s
          t == "0" || t.match?(/\A-?\d+(\.\d+)?\z/)
        end

        def number_or_zero(value)
          n = Float(value.to_s)
          format_number(n)
        rescue ArgumentError, TypeError
          "0"
        end

        def format_number(value)
          v = value.is_a?(Numeric) ? value : value.to_f
          if v.respond_to?(:finite?) && !v.finite?
            return v.to_s
          end

          (v.to_f % 1).zero? ? v.to_i.to_s : v.to_f.to_s
        end
      end
    end
  end
end
