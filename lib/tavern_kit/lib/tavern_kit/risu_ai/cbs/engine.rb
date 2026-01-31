# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Minimal CBS engine (Wave 5b).
      #
      # This starts with the escape/pure family and basic #if/#when semantics.
      # Later Wave 5 steps will expand this into the full CBS feature set.
      class Engine < TavernKit::Macro::Engine::Base
        OPEN = "{{"
        CLOSE = "}}"
        BLOCK_END_TOKEN = "/"

        def expand(text, environment:)
          # Per-parse state (mirrors upstream): functions persist across nested
          # call:: expansions, but reset for each top-level render.
          @functions = {}
          @call_stack = 0

          expand_with_call_stack(text.to_s, environment: environment)
        end

        private

        Block = Struct.new(:type, :mode, :keep, :expr, :args, keyword_init: true)

        def expand_stream(str, index, environment:, stop_on_end:)
          out = +""
          i = index

          while (open_idx = str.index(OPEN, i))
            out << str[i...open_idx]

            close_idx = find_close_idx(str, open_idx)
            unless close_idx
              out << str[open_idx..]
              return [out, str.length, false]
            end

            raw = str[(open_idx + OPEN.length)...close_idx]
            token = raw.to_s.strip

            if close_token?(token) && stop_on_end
              return [out, close_idx + CLOSE.length, true]
            end

            if token.start_with?("#")
              replacement, next_i = expand_block(str, open_idx: open_idx, close_idx: close_idx, token: token, environment: environment)
              if replacement
                out << replacement
                i = next_i
              else
                # Preserve original tag when the block can't be parsed yet.
                out << str[open_idx..(close_idx + CLOSE.length - 1)]
                i = close_idx + CLOSE.length
              end
              next
            end

            if close_token?(token)
              # Stray close tag at top-level is preserved.
              out << str[open_idx..(close_idx + CLOSE.length - 1)]
              i = close_idx + CLOSE.length
              next
            end

            out << expand_tag(raw, token: token, environment: environment)
            i = close_idx + CLOSE.length
          end

          out << str[i..] if i < str.length
          [out, str.length, false]
        end

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
          else
            nil
          end
        end

        def parse_block(token, environment:)
          name = token.delete_prefix("#")

          return Block.new(type: :pure) if name == "pure"
          return Block.new(type: :puredisplay) if name == "puredisplay" || name == "pure_display"
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
            block.mode == :keep ? inner : inner.strip
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
          s = expr.to_s.strip
          s = s[1..-2] if s.start_with?("[") && s.end_with?("]")

          parts = s.split(",").map { |v| v.strip }.reject(&:empty?)
          parts.map do |part|
            if (part.start_with?("\"") && part.end_with?("\"")) || (part.start_with?("'") && part.end_with?("'"))
              part[1..-2]
            elsif part.match?(/\A-?\d+\z/)
              part.to_i
            elsif part.match?(/\A-?\d+\.\d+\z/)
              part.to_f
            else
              part
            end
          end
        end

        def expand_with_call_stack(str, environment:)
          @call_stack += 1
          return "ERROR: Call stack limit reached" if @call_stack > 20

          out, = expand_stream(str, 0, environment: environment, stop_on_end: false)
          out
        ensure
          @call_stack -= 1
        end

        # Raw-mode parsing: nested block openers increment a counter so the next
        # close tag is treated as literal (prevents premature closing).
        def read_raw_until_close(str, index)
          out = +""
          i = index
          literal_closers = 0

          while (open_idx = str.index(OPEN, i))
            out << str[i...open_idx]

            close_idx = find_close_idx(str, open_idx)
            unless close_idx
              out << str[open_idx..]
              return [out, str.length, false]
            end

            raw = str[(open_idx + OPEN.length)...close_idx]
            token = raw.to_s.strip

            if token.start_with?("#") || token.start_with?(":")
              literal_closers += 1
              out << "#{OPEN}#{raw}#{CLOSE}"
              i = close_idx + CLOSE.length
              next
            end

            if close_token?(token)
              if literal_closers > 0
                literal_closers -= 1
                out << "#{OPEN}#{raw}#{CLOSE}"
                i = close_idx + CLOSE.length
                next
              end

              return [out, close_idx + CLOSE.length, true]
            end

            out << "#{OPEN}#{raw}#{CLOSE}"
            i = close_idx + CLOSE.length
          end

          out << str[i..] if i < str.length
          [out, str.length, false]
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
          s == "true" || s == "1"
        end

        def truthy_condition?(value, environment:)
          s = value.to_s.strip
          return truthy?(s) unless s.start_with?(OPEN) && s.end_with?(CLOSE)

          inner_raw = s.delete_prefix(OPEN).delete_suffix(CLOSE)
          token = inner_raw.to_s.strip
          truthy?(expand_tag(inner_raw, token: token, environment: environment))
        end

        def close_token?(token)
          t = token.to_s
          t.start_with?("/") && !t.start_with?("//") && t.strip == BLOCK_END_TOKEN
        end

        def find_close_idx(str, open_idx)
          i = open_idx + OPEN.length
          depth = 0

          while i < str.length
            next_open = str.index(OPEN, i)
            next_close = str.index(CLOSE, i)
            return nil unless next_close

            if next_open && next_open < next_close
              depth += 1
              i = next_open + OPEN.length
              next
            end

            if depth > 0
              depth -= 1
              i = next_close + CLOSE.length
              next
            end

            return next_close
          end

          nil
        end

        def chat_var(environment, name)
          environment.get_var(name, scope: :local)
        rescue NotImplementedError
          nil
        end

        def global_var(environment, name)
          environment.get_var(name, scope: :global)
        rescue NotImplementedError
          nil
        end

        def expand_tag(raw, token:, environment:)
          if token.start_with?("? ")
            return calc_token(token, environment: environment)
          end

          if token.start_with?("call::")
            rendered = expand_call(token, environment: environment)
            return rendered if rendered
          end

          case token
          when "bo" then "{{"
          when "bc" then "}}"
          when "decbo" then "{"
          when "decbc" then "}"
          when "br" then "\n"
          when "cbr" then "\\n"
          else
            parts = token.split("::")
            if parts.any?
              name = parts[0].to_s
              args = parts.drop(1)

              resolved = TavernKit::RisuAI::CBS::Macros.resolve(name, args, environment: environment)
              return resolved.to_s unless resolved.nil?
            end

            # Unknown tokens are preserved as-is for later expansion stages.
            "{{#{raw}}}"
          end
        end

        def expand_call(token, environment:)
          parts = token.split("::").drop(1)
          return nil if parts.empty?

          func_name = parts[0].to_s
          body = @functions[func_name]
          return nil unless body

          data = body.dup
          parts.each_with_index do |value, idx|
            data = data.gsub("{{arg::#{idx}}}", value.to_s)
          end

          expand_with_call_stack(data, environment: environment)
        end

        def calc_token(token, environment:)
          expr = token.delete_prefix("? ").to_s
          result = calc_string(expr, environment: environment)
          format_number(result)
        rescue StandardError
          "0"
        end

        def calc_string(text, environment:)
          depth = [+""]

          text.to_s.each_char do |ch|
            if ch == "("
              depth << +""
              next
            end

            if ch == ")" && depth.length > 1
              v = execute_rpn_calc(depth.pop, environment: environment)
              depth[-1] << format_number(v)
              next
            end

            depth[-1] << ch
          end

          execute_rpn_calc(depth.join, environment: environment)
        end

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
