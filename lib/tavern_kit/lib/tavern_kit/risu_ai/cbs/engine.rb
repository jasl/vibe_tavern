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

        ForceReturn = Class.new(StandardError) do
          attr_reader :value

          def initialize(value)
            super()
            @value = value
          end
        end

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

            out << expand_tag(raw, token: token, environment: environment, out_buffer: out)
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

        def expand_with_call_stack(str, environment:)
          @call_stack += 1
          return "ERROR: Call stack limit reached" if @call_stack > 20

          env = environment.respond_to?(:call_frame) ? environment.call_frame : environment

          out, = expand_stream(str, 0, environment: env, stop_on_end: false)
          out
        rescue ForceReturn => e
          e.value
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
          s == "1" || s.downcase == "true"
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
          t.start_with?("/") && !t.start_with?("//")
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

        def risu_escape(text)
          # Upstream: replaces { } ( ) with Private Use Area characters
          # \uE9B8-\uE9BB so downstream rendering can safely unescape later.
          text.to_s.gsub(/[{}()]/) do |ch|
            case ch
            when "{" then "\u{E9B8}"
            when "}" then "\u{E9B9}"
            when "(" then "\u{E9BA}"
            when ")" then "\u{E9BB}"
            else
              ch
            end
          end
        end

        def apply_bkspc!(out_buffer)
          # Upstream reference:
          # resources/Risuai/src/ts/cbs.ts (bkspc)
          return unless out_buffer

          root = out_buffer.to_s.rstrip
          out_buffer.replace(root.sub(/\s*\S+\z/, ""))
        end

        def apply_erase!(out_buffer)
          # Upstream reference:
          # resources/Risuai/src/ts/cbs.ts (erase)
          return unless out_buffer

          root = out_buffer.to_s.rstrip
          idx = root.rindex(/[.!?\n]/)

          if idx
            out_buffer.replace(root[0..idx].rstrip)
          else
            out_buffer.replace("")
          end
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

        def expand_tag(raw, token:, environment:, out_buffer: nil)
          raw_text = raw.to_s
          expanded_raw =
            if raw_text.include?(OPEN)
              # Nested tags inside {{...}} are expanded before macro lookup, like upstream.
              expanded, = expand_stream(raw_text, 0, environment: environment, stop_on_end: false)
              expanded.to_s
            else
              raw_text
            end

          tok = expanded_raw.strip

          return "" if tok.start_with?("//")

          if tok.start_with?("? ")
            return calc_token(tok, environment: environment)
          end

          if tok.start_with?("call::")
            rendered = expand_call(tok, environment: environment)
            return rendered if rendered
          end

          if tok == "bkspc"
            apply_bkspc!(out_buffer)
            return ""
          end

          if tok == "erase"
            apply_erase!(out_buffer)
            return ""
          end

          case tok
          # Upstream uses private-use glyphs to display braces without re-triggering CBS parsing.
          # resources/Risuai/src/ts/cbs.ts (decbo/decbc/bo/bc)
          when "bo" then "\u{E9B8}\u{E9B8}"
          when "bc" then "\u{E9B9}\u{E9B9}"
          when "decbo" then "\u{E9B8}"
          when "decbc" then "\u{E9B9}"
          when "br" then "\n"
          when "cbr" then "\\n"
          else
            parts =
              if expanded_raw.include?("::")
                expanded_raw.split("::")
              elsif expanded_raw.include?(":")
                expanded_raw.split(":")
              else
                [expanded_raw]
              end
            if parts.any?
              name = parts[0].to_s
              args = parts.drop(1)

              resolved = TavernKit::RisuAI::CBS::Macros.resolve(name, args, environment: environment)
              unless resolved.nil?
                if environment.respond_to?(:has_var?) &&
                   environment.has_var?("__force_return__", scope: :temp) &&
                   truthy?(environment.get_var("__force_return__", scope: :temp))
                  value = environment.get_var("__return__", scope: :temp)
                  raise ForceReturn, value.nil? ? "null" : value.to_s
                end

                return resolved.to_s
              end
            end

            # Unknown tokens are preserved as-is for later expansion stages.
            "{{#{expanded_raw}}}"
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

        # RPN math helpers extracted to `risu_ai/cbs/engine/rpn_calc.rb` (Wave 6).
      end
    end
  end
end

require_relative "engine/rpn_calc"
