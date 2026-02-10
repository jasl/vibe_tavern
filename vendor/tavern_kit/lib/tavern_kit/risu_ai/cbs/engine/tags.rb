# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Tag expansion helpers for `Engine`.
      #
      # Pure refactor: extracted from `risu_ai/cbs/engine.rb`.
      class Engine < TavernKit::Macro::Engine::Base
        private

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

            # Unknown tokens are preserved as-is for later expansion steps.
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
      end
    end
  end
end
