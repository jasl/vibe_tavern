# frozen_string_literal: true

require "json"

module AgentCore
  module Contrib
    module Directives
      module Parser
        DEFAULT_MAX_BYTES = 200_000

        module_function

        def parse_json(content, max_bytes: DEFAULT_MAX_BYTES)
          return { ok: true, value: content } if content.is_a?(Hash)

          str = content.to_s.strip
          return { ok: false, code: "EMPTY", error: "empty content" } if str.empty?
          if str.bytesize > max_bytes
            return { ok: false, code: "TOO_LARGE", error: "content too large", details: { max_bytes: max_bytes } }
          end

          candidate = unwrap_content(str)
          parse_object(candidate) || parse_object(extract_first_json_object(candidate)) || invalid_json(candidate)
        end

        def unwrap_content(str)
          s = unwrap_xmlish_tag(str, "directives") || unwrap_xmlish_tag(str, "json") || str
          unwrap_code_fence(s) || s
        end
        private_class_method :unwrap_content

        def unwrap_xmlish_tag(str, tag)
          m = str.match(%r{<#{Regexp.escape(tag)}>\s*(.+?)\s*</#{Regexp.escape(tag)}>}m)
          m ? m[1].to_s : nil
        end
        private_class_method :unwrap_xmlish_tag

        def unwrap_code_fence(str)
          m = str.match(/\A```(?:json)?\s*(.+?)\s*```\z/m)
          m ? m[1].to_s : nil
        end
        private_class_method :unwrap_code_fence

        def parse_object(str)
          return nil if str.nil?

          obj = JSON.parse(str)
          return { ok: true, value: obj } if obj.is_a?(Hash)

          { ok: false, code: "NOT_OBJECT", error: "root must be a JSON object" }
        rescue JSON::ParserError, TypeError
          nil
        end
        private_class_method :parse_object

        def invalid_json(str)
          { ok: false, code: "INVALID_JSON", error: "unable to parse JSON", details: { sample: str[0, 200] } }
        end
        private_class_method :invalid_json

        def extract_first_json_object(str)
          input = str.to_s
          start = input.index("{")
          return nil unless start

          in_string = false
          escaped = false
          depth = 0

          input.chars.each_with_index do |ch, idx|
            next if idx < start

            if in_string
              if escaped
                escaped = false
              elsif ch == "\\"
                escaped = true
              elsif ch == "\""
                in_string = false
              end
              next
            end

            case ch
            when "\""
              in_string = true
            when "{"
              depth += 1
            when "}"
              depth -= 1
              return input[start..idx] if depth.zero?
            end
          end

          nil
        end
        private_class_method :extract_first_json_object
      end
    end
  end
end
