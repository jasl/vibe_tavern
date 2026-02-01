# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      # Internal parser methods for `V2Engine`.
      #
      # Pure refactor: extracted from `silly_tavern/macro/v2_engine.rb` (Wave 6 large-file split).
      class V2Engine < TavernKit::Macro::Engine::Base
        private

        def find_matching_closing(text, start_idx, target_key)
          depth = 1
          i = start_idx.to_i
          str = text.to_s

          while i < str.length
            open = str.index("{{", i)
            return nil if open.nil?

            close = find_macro_close(str, open)
            return nil if close.nil?

            inner = str[(open + 2)...close].to_s
            info = parse_macro_inner(inner)
            if info
              key = info[:key]
              if key == target_key
                if info[:flags].closing_block?
                  depth -= 1
                  return { open: open, close: close } if depth.zero?
                else
                  defn = @registry.respond_to?(:get) ? @registry.get(key) : nil
                  depth += 1 if defn.nil? || defn.accepts_scoped_content?(info[:args].length)
                end
              end
            end

            i = close + 2
          end

          nil
        end

        # Find the closing "}}" for a macro starting at `open` (the index of "{{"),
        # supporting nested macros like `{{outer::{{inner}}}}`.
        def find_macro_close(text, open)
          str = text.to_s
          depth = 1
          i = open.to_i + 2

          while i < str.length
            next_open = str.index("{{", i)
            next_close = str.index("}}", i)
            return nil if next_open.nil? && next_close.nil?

            if next_close.nil? || (!next_open.nil? && next_open < next_close)
              depth += 1
              i = next_open + 2
            else
              depth -= 1
              return next_close if depth.zero?

              i = next_close + 2
            end
          end

          nil
        end

        def parse_macro_inner(raw_inner)
          s = raw_inner.to_s
          len = s.length
          i = 0

          i += 1 while i < len && whitespace?(s.getbyte(i))
          return nil if i >= len

          # Special-case comment closing tag: {{///}}.
          if s.getbyte(i) == "/".ord && s[i, 3] == "///"
            rest = s[(i + 3)..].to_s
            if rest.strip.empty?
              return {
                name: "//",
                key: "//",
                flags: Flags.parse(["/"]),
                args: [],
              }
            end
          end

          # Special-case comment macro identifier: {{// ...}}.
          if s[i, 2] == "//"
            name = "//"
            key = "//"
            args, = parse_args(s, i + 2)
            return { name: name, key: key, flags: Flags.empty, args: args }
          end

          flags_symbols = []
          loop do
            i += 1 while i < len && whitespace?(s.getbyte(i))
            break if i >= len

            ch = s.getbyte(i)
            break unless flag_byte?(ch)

            flags_symbols << ch.chr
            i += 1
          end

          flags = Flags.parse(flags_symbols)

          i += 1 while i < len && whitespace?(s.getbyte(i))
          return nil if i >= len

          name_start = i
          while i < len
            break if whitespace?(s.getbyte(i))
            break if s.getbyte(i) == ":".ord

            i += 1
          end

          name = s[name_start...i].to_s.strip
          return nil if name.empty?

          args, = parse_args(s, i)
          { name: name, key: name.downcase, flags: flags, args: args }
        end

        def parse_args(raw_inner, start_idx)
          s = raw_inner.to_s
          len = s.length
          i = start_idx.to_i

          i += 1 while i < len && whitespace?(s.getbyte(i))
          if s.getbyte(i) == ":".ord
            i += s.getbyte(i + 1) == ":".ord ? 2 : 1
          end

          spans = []
          i += 1 while i < len && whitespace?(s.getbyte(i))
          return [spans, i] if i >= len

          depth = 0
          seg_start = i
          cursor = i

          while cursor < len
            if s[cursor, 2] == "{{"
              depth += 1
              cursor += 2
              next
            end

            if s[cursor, 2] == "}}"
              depth -= 1 if depth.positive?
              cursor += 2
              next
            end

            if depth.zero? && s[cursor, 2] == "::"
              spans << build_arg_span(s, seg_start, cursor)
              cursor += 2
              seg_start = cursor
              seg_start += 1 while seg_start < len && whitespace?(s.getbyte(seg_start))
              cursor = seg_start
              next
            end

            cursor += 1
          end

          spans << build_arg_span(s, seg_start, len)
          [spans, len]
        end

        def build_arg_span(str, left, right)
          l = left.to_i
          r = right.to_i

          l += 1 while l < r && whitespace?(str.getbyte(l))
          r -= 1 while r > l && whitespace?(str.getbyte(r - 1))

          ArgSpan.new(raw: str[l...r], start_offset: l, end_offset: r - 1)
        end
      end
    end
  end
end
