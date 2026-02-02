# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Block parsing and evaluation helpers for `Engine`.
      #
      # Pure refactor: extracted from `risu_ai/cbs/engine.rb`.
      class Engine < TavernKit::Macro::Engine::Base
        private

        def expand_block(str, open_idx:, close_idx:, token:, environment:)
          block = parse_block(token, environment: environment)
          return unless block

          inner_start = close_idx + CLOSE.length

          case block.type
          when :ignore
            _, next_i, ended = read_raw_until_close(str, inner_start)
            return unless ended
            ["", next_i]
          when :pure, :puredisplay, :escape
            inner_raw, next_i, ended = read_raw_until_close(str, inner_start)
            return unless ended
            [eval_raw_block(block, inner_raw), next_i]
          when :each
            inner_raw, next_i, ended = read_raw_until_close(str, inner_start)
            return unless ended
            [eval_each(block, inner_raw, environment: environment), next_i]
          when :func
            inner_raw, next_i, ended = read_raw_until_close(str, inner_start)
            return unless ended

            func_name = block.expr.to_s
            @functions[func_name] = inner_raw.strip unless func_name.empty?
            ["", next_i]
          when :parse, :ifpure, :newif, :newif_falsy
            inner_eval, next_i, ended = expand_stream(str, inner_start, environment: environment, stop_on_end: true)
            return unless ended
            [eval_parsed_block(block, inner_eval), next_i]
          when :code
            inner_eval, next_i, ended = expand_stream(str, inner_start, environment: environment, stop_on_end: true)
            return unless ended
            [normalize_code(inner_eval), next_i]
          else
            nil
          end
        end

        def parse_block(token, environment:)
          name = token.delete_prefix("#")

          return Block.new(type: :pure) if name == "pure"
          return Block.new(type: :puredisplay) if name == "puredisplay" || name == "pure_display"
          return Block.new(type: :code) if name == "code"
          if name.start_with?("escape")
            mode = name.include?("::keep") ? :keep : nil
            return Block.new(type: :escape, mode: mode)
          end

          if name.start_with?("each")
            rest = name.delete_prefix("each").strip
            mode = nil

            if rest.start_with?("::keep ")
              mode = :keep
              rest = rest.delete_prefix("::keep ").strip
            end

            rest = rest.delete_prefix("as ").strip if rest.start_with?("as ")
            return Block.new(type: :each, mode: mode, expr: rest)
          end

          if name.start_with?("func")
            parts = name.split
            return nil if parts.length < 2

            func_name = parts[1].to_s
            return nil if func_name.empty?

            return Block.new(type: :func, expr: func_name, args: parts.drop(2))
          end

          if name.start_with?("if_pure ")
            state = name.split(" ", 2)[1].to_s
            return truthy_condition?(state, environment: environment) ? Block.new(type: :ifpure) : Block.new(type: :ignore)
          end

          if name.start_with?("if ")
            state = name.split(" ", 2)[1].to_s
            return truthy_condition?(state, environment: environment) ? Block.new(type: :parse) : Block.new(type: :ignore)
          end

          if name.start_with?("when ")
            state = name.split(" ", 2)[1].to_s
            return truthy_condition?(state, environment: environment) ? Block.new(type: :newif) : Block.new(type: :newif_falsy)
          end

          if name.start_with?("when::")
            statement = name.split("::").drop(1)
            return parse_when_statement(statement, environment: environment)
          end

          nil
        end

        def parse_when_statement(statement, environment:)
          if statement.length == 1
            state = statement[0].to_s
            return truthy_condition?(state, environment: environment) ? Block.new(type: :newif) : Block.new(type: :newif_falsy)
          end

          mode = :normal
          parts = statement.dup

          while parts.length > 1
            condition = parts.pop.to_s
            operator = parts.pop.to_s

            case operator
            when "not"
              parts << (truthy_condition?(condition, environment: environment) ? "0" : "1")
            when "keep"
              mode = :keep
              parts << condition
            when "legacy"
              mode = :legacy
              parts << condition
            when "and"
              condition2 = parts.pop.to_s
              parts << (truthy_condition?(condition, environment: environment) && truthy_condition?(condition2, environment: environment) ? "1" : "0")
            when "or"
              condition2 = parts.pop.to_s
              parts << (truthy_condition?(condition, environment: environment) || truthy_condition?(condition2, environment: environment) ? "1" : "0")
            when "is"
              condition2 = parts.pop.to_s
              parts << (condition == condition2 ? "1" : "0")
            when "isnot"
              condition2 = parts.pop.to_s
              parts << (condition != condition2 ? "1" : "0")
            when ">"
              condition2 = parts.pop.to_s
              parts << (condition2.to_f > condition.to_f ? "1" : "0")
            when "<"
              condition2 = parts.pop.to_s
              parts << (condition2.to_f < condition.to_f ? "1" : "0")
            when ">="
              condition2 = parts.pop.to_s
              parts << (condition2.to_f >= condition.to_f ? "1" : "0")
            when "<="
              condition2 = parts.pop.to_s
              parts << (condition2.to_f <= condition.to_f ? "1" : "0")
            when "var"
              parts << (truthy_condition?(chat_var(environment, condition), environment: environment) ? "1" : "0")
            when "toggle"
              parts << (truthy_condition?(global_var(environment, "toggle_#{condition}"), environment: environment) ? "1" : "0")
            when "vis"
              var_name = parts.pop.to_s
              parts << (chat_var(environment, var_name).to_s == condition ? "1" : "0")
            when "visnot"
              var_name = parts.pop.to_s
              parts << (chat_var(environment, var_name).to_s != condition ? "1" : "0")
            when "tis"
              toggle_name = parts.pop.to_s
              parts << (global_var(environment, "toggle_#{toggle_name}").to_s == condition ? "1" : "0")
            when "tisnot"
              toggle_name = parts.pop.to_s
              parts << (global_var(environment, "toggle_#{toggle_name}").to_s != condition ? "1" : "0")
            else
              parts << (truthy_condition?(condition, environment: environment) ? "1" : "0")
            end
          end

          final_condition = parts[0].to_s

          if truthy?(final_condition)
            case mode
            when :keep
              Block.new(type: :newif, keep: true)
            when :legacy
              Block.new(type: :parse)
            else
              Block.new(type: :newif)
            end
          else
            case mode
            when :keep
              Block.new(type: :newif_falsy, keep: true)
            when :legacy
              Block.new(type: :ignore)
            else
              Block.new(type: :newif_falsy)
            end
          end
        end

        def eval_raw_block(block, inner)
          case block.type
          when :pure
            inner.strip
          when :puredisplay
            inner.strip.gsub("{{", "\\{\\{").gsub("}}", "\\}\\}")
          when :escape
            text = block.mode == :keep ? inner : inner.strip
            risu_escape(text)
          else
            ""
          end
        end

        def eval_parsed_block(block, inner)
          case block.type
          when :parse
            trim_lines(inner.strip)
          when :ifpure
            inner
          when :newif
            eval_newif(inner, truthy: true, keep: block.keep == true)
          when :newif_falsy
            eval_newif(inner, truthy: false, keep: block.keep == true)
          else
            ""
          end
        end

        def eval_each(block, inner, environment:)
          template =
            if block.mode == :keep
              inner
            else
              trim_lines(inner.strip)
            end

          array, var_name = parse_each_expr(block.expr.to_s)
          return "" if array.empty? || var_name.to_s.strip.empty?

          out = +""
          slot = "{{slot::#{var_name}}}"

          array.each do |value|
            rendered =
              if value.is_a?(String)
                value
              else
                ::JSON.generate(value)
              end
            out << template.gsub(slot, rendered)
          end

          out = out.strip unless block.mode == :keep
          expanded, = expand_stream(out, 0, environment: environment, stop_on_end: false)
          expanded
        end

        def parse_each_expr(expr)
          s = expr.to_s

          as_index = s.rindex(" as ")
          if as_index
            array_expr = s[0...as_index]
            var_name = s[(as_index + 4)..]
            return [parse_array(array_expr), var_name.to_s.strip]
          end

          last_space = s.rindex(" ")
          return [[], nil] unless last_space

          array_expr = s[0...last_space]
          var_name = s[(last_space + 1)..]
          [parse_array(array_expr), var_name.to_s.strip]
        end

        def parse_array(expr)
          # Upstream: JSON.parse when possible; otherwise split by "§".
          s = expr.to_s.strip

          begin
            arr = ::JSON.parse(s)
            return arr if arr.is_a?(Array)
          rescue ::JSON::ParserError
            nil
          end

          s.split("§")
        end

        def eval_newif(text, truthy:, keep:)
          lines = text.split("\n")

          if lines.length == 1
            else_token = "{{:else}}"
            else_index = text.index(else_token)

            if else_index
              if truthy
                return text[0...else_index]
              end

              return text[(else_index + else_token.length)..].to_s
            end

            return truthy ? text : ""
          end

          else_line = lines.find_index { |v| v.strip == "{{:else}}" }

          if else_line
            lines =
              if truthy
                lines[0...else_line]
              else
                lines[(else_line + 1)..] || []
              end
          else
            return "" unless truthy
          end

          unless keep
            lines.shift while lines.any? && lines[0].strip.empty?
            lines.pop while lines.any? && lines[-1].strip.empty?
          end

          lines.join("\n")
        end

        def trim_lines(text)
          text.split("\n").map(&:lstrip).join("\n").strip
        end

        def truthy?(value)
          s = value.to_s
          s == "1" || s.downcase == "true"
        end

        def truthy_condition?(value, environment:)
          s = value.to_s.strip
          return truthy?(s) unless s.start_with?(OPEN) && s.end_with?(CLOSE)

          inner_raw = s.delete_prefix(OPEN).delete_suffix(CLOSE)
          token = inner_raw.to_s.strip
          truthy?(expand_tag(inner_raw, token: token, environment: environment))
        end

        def normalize_code(text)
          # Upstream: trim -> remove newlines/tabs -> process \uXXXX and other escapes.
          t = text.to_s.strip
          t = t.delete("\n").delete("\t")

          t = t.gsub(/\\u([0-9A-Fa-f]{4})/) do
            Regexp.last_match(1).to_i(16).chr(Encoding::UTF_8)
          end

          t.gsub(/\\(.)/) do
            ch = Regexp.last_match(1)
            case ch
            when "n" then "\n"
            when "r" then "\r"
            when "t" then "\t"
            when "b" then "\b"
            when "f" then "\f"
            when "v" then "\v"
            when "a" then "\a"
            when "x" then "\x00"
            else
              ch
            end
          end
        end
      end
    end
  end
end
