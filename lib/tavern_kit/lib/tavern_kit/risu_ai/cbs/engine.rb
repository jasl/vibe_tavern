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

            close_idx = str.index(CLOSE, open_idx + OPEN.length)
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
            return ["", next_i]
          when :pure, :puredisplay, :escape
            inner_raw, next_i, ended = read_raw_until_close(str, inner_start)
            return unless ended
            return [eval_raw_block(block, inner_raw), next_i]
          when :each
            inner_raw, next_i, ended = read_raw_until_close(str, inner_start)
            return unless ended
            return [eval_each(block, inner_raw, environment: environment), next_i]
          when :func
            inner_raw, next_i, ended = read_raw_until_close(str, inner_start)
            return unless ended

            func_name = block.expr.to_s
            @functions[func_name] = inner_raw.strip unless func_name.empty?
            return ["", next_i]
          when :parse, :ifpure, :newif, :newif_falsy
            inner_eval, next_i, ended = expand_stream(str, inner_start, environment: environment, stop_on_end: true)
            return unless ended
            return [eval_parsed_block(block, inner_eval), next_i]
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
            return truthy?(state) ? Block.new(type: :ifpure) : Block.new(type: :ignore)
          end

          if name.start_with?("if ")
            state = name.split(" ", 2)[1].to_s
            return truthy?(state) ? Block.new(type: :parse) : Block.new(type: :ignore)
          end

          if name.start_with?("when ")
            state = name.split(" ", 2)[1].to_s
            return truthy?(state) ? Block.new(type: :newif) : Block.new(type: :newif_falsy)
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
            return truthy?(state) ? Block.new(type: :newif) : Block.new(type: :newif_falsy)
          end

          mode = :normal
          parts = statement.dup

          while parts.length > 1
            condition = parts.pop.to_s
            operator = parts.pop.to_s

            case operator
            when "not"
              parts << (truthy?(condition) ? "0" : "1")
            when "keep"
              mode = :keep
              parts << condition
            when "legacy"
              mode = :legacy
              parts << condition
            when "and"
              condition2 = parts.pop.to_s
              parts << (truthy?(condition) && truthy?(condition2) ? "1" : "0")
            when "or"
              condition2 = parts.pop.to_s
              parts << (truthy?(condition) || truthy?(condition2) ? "1" : "0")
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
              parts << (truthy?(chat_var(environment, condition)) ? "1" : "0")
            when "toggle"
              parts << (truthy?(global_var(environment, "toggle_#{condition}")) ? "1" : "0")
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
              parts << (truthy?(condition) ? "1" : "0")
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

            close_idx = str.index(CLOSE, open_idx + OPEN.length)
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

        def close_token?(token)
          t = token.to_s
          t.start_with?("/") && !t.start_with?("//") && t.strip == BLOCK_END_TOKEN
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
      end
    end
  end
end
