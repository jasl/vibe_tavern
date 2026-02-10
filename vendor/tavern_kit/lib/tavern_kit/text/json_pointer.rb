# frozen_string_literal: true

module TavernKit
  module Text
    # RFC 6901 JSON Pointer utilities (syntax-level).
    module JSONPointer
      module_function

      def escape(token)
        token.to_s.gsub("~", "~0").gsub("/", "~1")
      end

      def unescape(token)
        s = token.to_s
        out = +""

        i = 0
        while i < s.length
          ch = s[i]
          if ch == "~"
            nxt = s[i + 1]
            raise ArgumentError, "Invalid JSON Pointer escape (trailing '~')" if nxt.nil?

            case nxt
            when "0"
              out << "~"
            when "1"
              out << "/"
            else
              raise ArgumentError, "Invalid JSON Pointer escape: ~#{nxt}"
            end

            i += 2
          else
            out << ch
            i += 1
          end
        end

        out
      end

      def tokens(pointer)
        raise ArgumentError, "pointer must be a String" unless pointer.is_a?(String)

        return [] if pointer.empty?
        raise ArgumentError, "JSON Pointer must start with '/'" unless pointer.start_with?("/")

        pointer.split("/", -1)[1..].map { |t| unescape(t) }
      end

      def from_tokens(tokens)
        list = Array(tokens).map { |t| escape(t) }
        return "" if list.empty?

        "/" + list.join("/")
      end

      def valid?(pointer)
        tokens(pointer)
        true
      rescue StandardError
        false
      end
    end
  end
end
