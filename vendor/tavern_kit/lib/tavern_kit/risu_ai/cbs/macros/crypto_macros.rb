# frozen_string_literal: true

require "base64"

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_xor(args)
          bytes = args[0].to_s.encode(Encoding::UTF_8).bytes.map { |b| b ^ 0xFF }
          ::Base64.strict_encode64(bytes.pack("C*"))
        rescue StandardError
          ""
        end
        private_class_method :resolve_xor

        def resolve_xordecrypt(args)
          raw = ::Base64.strict_decode64(args[0].to_s)
          bytes = raw.bytes.map { |b| b ^ 0xFF }
          bytes.pack("C*").force_encoding(Encoding::UTF_8).scrub
        rescue ArgumentError
          ""
        end
        private_class_method :resolve_xordecrypt

        def resolve_crypt(args)
          text = args[0].to_s
          shift_raw = args[1].to_s

          shift =
            if shift_raw.empty?
              32_768
            else
              n = js_number(shift_raw)
              (n.nan? || n.infinite?) ? 32_768 : n.to_i
            end

          utf16 = text.encode(Encoding::UTF_16LE, invalid: :replace, undef: :replace)
          out_bytes = []

          utf16.bytes.each_slice(2) do |lo, hi|
            unit = lo.to_i + (hi.to_i << 8)
            shifted = (unit + shift) & 0xFFFF
            out_bytes << (shifted & 0xFF)
            out_bytes << ((shifted >> 8) & 0xFF)
          end

          out_bytes.pack("C*")
                   .force_encoding(Encoding::UTF_16LE)
                   .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        rescue StandardError
          ""
        end
        private_class_method :resolve_crypt
      end
    end
  end
end
