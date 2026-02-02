# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Internal parsing helpers for `Engine`.
      #
      # Pure refactor: extracted from `risu_ai/cbs/engine.rb`.
      class Engine < TavernKit::Macro::Engine::Base
        private

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
      end
    end
  end
end
