# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolsBuilder
      module Support
        module Utf8
          module_function

          def truncate_utf8_bytes(value, max_bytes:)
            max_bytes = Integer(max_bytes)
            return "" if max_bytes <= 0

            str = normalize_utf8(value)
            return str if str.bytesize <= max_bytes

            sliced = str.byteslice(0, max_bytes).to_s
            normalize_utf8(sliced)
          rescue ArgumentError, TypeError
            ""
          end

          def normalize_utf8(value)
            str = value.to_s
            str = str.dup.force_encoding(Encoding::UTF_8)
            return str if str.valid_encoding?

            str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
          rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
            str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
          end
        end
      end
    end
  end
end
