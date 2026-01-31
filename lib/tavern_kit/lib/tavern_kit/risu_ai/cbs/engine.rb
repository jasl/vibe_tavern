# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Minimal CBS engine (Wave 5b kickoff).
      #
      # This starts with the escape/pure family and preserves unknown macros.
      # Later Wave 5 steps will expand this into the full CBS feature set.
      class Engine < TavernKit::Macro::Engine::Base
        OPEN = "{{"
        CLOSE = "}}"
        BLOCK_END = "{{/}}"

        def expand(text, environment:)
          # CBS is tolerant by default: malformed/unknown tokens are preserved.
          expand_string(text.to_s, environment: environment)
        end

        private

        Block = Struct.new(:type, :mode, keyword_init: true)

        def expand_string(str, environment:)
          out = +""
          i = 0

          while (open_idx = str.index(OPEN, i))
            out << str[i...open_idx]

            close_idx = str.index(CLOSE, open_idx + OPEN.length)
            unless close_idx
              out << str[open_idx..]
              return out
            end

            raw = str[(open_idx + OPEN.length)...close_idx]
            token = raw.to_s.strip

            if token.start_with?("#")
              replacement, next_i = expand_block(str, open_idx: open_idx, close_idx: close_idx, token: token)
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

            out << expand_tag(raw, token: token, environment: environment)
            i = close_idx + CLOSE.length
          end

          out << str[i..] if i < str.length
          out
        end

        def expand_block(str, open_idx:, close_idx:, token:)
          block = parse_block(token)
          return unless block

          inner_start = close_idx + CLOSE.length
          end_idx = str.index(BLOCK_END, inner_start)
          return unless end_idx

          inner = str[inner_start...end_idx]
          [eval_block(block, inner), end_idx + BLOCK_END.length]
        end

        def parse_block(token)
          name = token.delete_prefix("#")

          return Block.new(type: :pure) if name == "pure"
          return Block.new(type: :puredisplay) if name == "puredisplay" || name == "pure_display"

          if name.start_with?("escape")
            mode = name.include?("::keep") ? :keep : nil
            return Block.new(type: :escape, mode: mode)
          end

          nil
        end

        def eval_block(block, inner)
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

        def expand_tag(raw, token:, environment:)
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
      end
    end
  end
end

