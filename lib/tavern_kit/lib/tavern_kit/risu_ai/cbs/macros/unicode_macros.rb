# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_unicodeencode(args)
          s = args[0].to_s
          return "NaN" if s.empty?

          index_raw = args[1].to_s
          index =
            if index_raw.empty?
              0
            else
              n = js_number(index_raw)
              (n.nan? || n.infinite?) ? 0 : n.to_i
            end

          code_unit = utf16_code_unit_at(s, index)
          code_unit.nil? ? "NaN" : code_unit.to_s
        rescue StandardError
          "NaN"
        end
        private_class_method :resolve_unicodeencode

        def resolve_unicodedecode(args)
          num = js_number(args[0])
          num = 0.0 if num.nan? || num.infinite?
          from_utf16_code_unit(num.to_i)
        rescue StandardError
          ""
        end
        private_class_method :resolve_unicodedecode

        def resolve_u(args)
          int = js_parse_int(args[0], 16)
          from_utf16_code_unit(int || 0)
        rescue StandardError
          ""
        end
        private_class_method :resolve_u

        def resolve_ue(args)
          resolve_u(args)
        end
        private_class_method :resolve_ue

        def resolve_fromhex(args)
          int = js_parse_int(args[0], 16)
          int.nil? ? "NaN" : int.to_s
        end
        private_class_method :resolve_fromhex

        def resolve_tohex(args)
          int = js_parse_int(args[0], 10)
          int.nil? ? "NaN" : int.to_s(16)
        end
        private_class_method :resolve_tohex

        def utf16_code_unit_at(str, index)
          return nil if index.negative?

          utf16 = str.to_s.encode(Encoding::UTF_16LE, invalid: :replace, undef: :replace)
          offset = index * 2
          return nil if (offset + 1) >= utf16.bytesize

          lo = utf16.getbyte(offset)
          hi = utf16.getbyte(offset + 1)
          lo + (hi << 8)
        end
        private_class_method :utf16_code_unit_at

        def from_utf16_code_unit(num)
          code_unit = num.to_i & 0xFFFF
          bytes = [code_unit].pack("v")
          bytes.force_encoding(Encoding::UTF_16LE)
               .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end
        private_class_method :from_utf16_code_unit

        def js_parse_int(value, base)
          s = value.to_s.strip

          pattern =
            if base.to_i == 16
              /\A[+-]?[0-9a-fA-F]+/
            else
              /\A[+-]?\d+/
            end

          m = s.match(pattern)
          return nil unless m

          Integer(m[0], base)
        rescue ArgumentError, TypeError
          nil
        end
        private_class_method :js_parse_int
      end
    end
  end
end
