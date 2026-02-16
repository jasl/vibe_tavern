# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module Truncation
        module_function

        DEFAULT_MARKER = "\n...\n"

        def normalize_utf8(value)
          str = value.to_s
          str = str.dup.force_encoding(Encoding::UTF_8)
          return str if str.valid_encoding?

          str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
        end

        def truncate_utf8_tail_bytes(value, max_bytes:)
          max_bytes = Integer(max_bytes)
          return "" if max_bytes <= 0

          str = normalize_utf8(value)
          return str if str.bytesize <= max_bytes

          sliced = str.byteslice(str.bytesize - max_bytes, max_bytes).to_s
          sliced = sliced.dup.force_encoding(Encoding::UTF_8)

          while !sliced.valid_encoding? && sliced.bytesize.positive?
            sliced = sliced.byteslice(1, sliced.bytesize - 1).to_s
            sliced.force_encoding(Encoding::UTF_8)
          end

          sliced.valid_encoding? ? sliced : ""
        rescue ArgumentError, TypeError
          ""
        end

        def head_marker_tail(value, max_bytes:, marker: DEFAULT_MARKER)
          max_bytes = Integer(max_bytes)
          return "" if max_bytes <= 0

          str = normalize_utf8(value)
          return str if str.bytesize <= max_bytes

          marker = normalize_utf8(marker.to_s)
          marker = DEFAULT_MARKER if marker.empty?

          if marker.bytesize >= max_bytes
            return AgentCore::Utils.truncate_utf8_bytes(str, max_bytes: max_bytes)
          end

          remaining = max_bytes - marker.bytesize
          head_bytes = remaining / 2
          tail_bytes = remaining - head_bytes

          head = AgentCore::Utils.truncate_utf8_bytes(str, max_bytes: head_bytes)
          tail = truncate_utf8_tail_bytes(str, max_bytes: tail_bytes)

          "#{head}#{marker}#{tail}"
        rescue ArgumentError, TypeError
          ""
        end
      end
    end
  end
end
