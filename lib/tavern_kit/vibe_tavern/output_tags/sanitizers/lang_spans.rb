# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module OutputTags
      module Sanitizers
        module LangSpans
          module_function

          def call(text, cfg)
            validate_code = fetch_bool(cfg, :validate_code, default: true)
            auto_close = fetch_bool(cfg, :auto_close, default: true)

            on_invalid_code = cfg.fetch(:on_invalid_code, :strip)
            raise ArgumentError, "on_invalid_code must be a Symbol" unless on_invalid_code.is_a?(Symbol)
            unless %i[strip keep drop].include?(on_invalid_code)
              raise ArgumentError, "on_invalid_code not supported: #{on_invalid_code.inspect}"
            end

            sanitize(
              text.to_s,
              validate_code: validate_code,
              auto_close: auto_close,
              on_invalid_code: on_invalid_code,
            )
          rescue StandardError => e
            [text.to_s, ["output_tags.lang_spans: #{e.class}: #{e.message}"]]
          end

          def fetch_bool(cfg, key, default:)
            return default unless cfg.key?(key)

            TavernKit::Coerce.bool(cfg.fetch(key), default: default)
          end
          private_class_method :fetch_bool

          def sanitize(text, validate_code:, auto_close:, on_invalid_code:)
            out = +""
            warnings = []
            stack = []
            drop_depth = 0

            tag_re = /<\s*(\/?)\s*lang\b([^>]*)>/im
            pos = 0

            while (m = tag_re.match(text, pos))
              out << text[pos...m.begin(0)] if drop_depth.zero?

              is_close = !m[1].to_s.empty?
              raw_attrs = m[2].to_s

              if is_close
                if stack.empty?
                  warnings << "output_tags.lang_spans: stray closing </lang> removed"
                else
                  entry = stack.pop
                  drop_depth -= 1 if entry[:mode] == :drop && drop_depth.positive?
                  out << "</lang>" if drop_depth.zero? && entry[:mode] == :keep
                end
              elsif drop_depth.positive?
                stack << { mode: :drop }
                drop_depth += 1
              else
                code_raw, pairs = extract_lang_code(raw_attrs)
                code_str = code_raw.to_s.strip

                canonical = canonicalize_bcp47(code_str)

                if validate_code && canonical.nil?
                  if code_str.empty?
                    warnings << "output_tags.lang_spans: missing code attribute (stripping <lang> wrapper)"
                  else
                    warnings << "output_tags.lang_spans: invalid code=#{code_str.inspect} (stripping <lang> wrapper)"
                  end

                  case on_invalid_code
                  when :keep
                    out << "<lang#{raw_attrs}>"
                    stack << { mode: :keep }
                  when :drop
                    stack << { mode: :drop }
                    drop_depth += 1
                  else
                    stack << { mode: :strip }
                  end
                else
                  code_value = canonical || code_str
                  out << "<lang#{rebuild_attrs(pairs, code: code_value)}>"
                  stack << { mode: :keep }
                end
              end

              pos = m.end(0)
            end

            out << text[pos..] if drop_depth.zero? && pos < text.length

            if auto_close
              until stack.empty?
                entry = stack.pop
                drop_depth -= 1 if entry[:mode] == :drop && drop_depth.positive?
                out << "</lang>" if drop_depth.zero? && entry[:mode] == :keep
              end
            elsif stack.any? { |entry| entry[:mode] == :keep }
              warnings << "output_tags.lang_spans: unclosed <lang> span detected"
            end

            [out, warnings.uniq]
          end
          private_class_method :sanitize

          def extract_lang_code(raw_attrs)
            pairs = parse_attrs(raw_attrs)
            code = nil

            pairs.each do |key, value|
              next unless key.to_s.strip.downcase == "code"

              code = strip_quotes(value)
              break
            end

            [code, pairs]
          rescue StandardError
            [nil, []]
          end
          private_class_method :extract_lang_code

          def strip_quotes(value)
            s = value.to_s.strip
            return s if s.length < 2

            if (s.start_with?("\"") && s.end_with?("\"")) || (s.start_with?("'") && s.end_with?("'"))
              s[1..-2]
            else
              s
            end
          rescue StandardError
            value.to_s
          end
          private_class_method :strip_quotes

          def canonicalize_bcp47(value)
            raw = value.to_s.strip
            return nil if raw.empty?

            tag = raw.tr("_", "-")
            return nil unless bcp47_valid?(tag)

            parts = tag.split("-")
            out = []

            out << parts.shift.to_s.downcase

            if parts.first&.match?(/\A[A-Za-z]{4}\z/)
              script = parts.shift.to_s
              out << script[0].to_s.upcase + script[1..].to_s.downcase
            end

            if parts.first&.match?(/\A[A-Za-z]{2}\z/)
              out << parts.shift.to_s.upcase
            elsif parts.first&.match?(/\A\d{3}\z/)
              out << parts.shift.to_s
            end

            parts.each { |p| out << p.to_s.downcase }

            out.join("-")
          rescue StandardError
            nil
          end
          private_class_method :canonicalize_bcp47

          def bcp47_valid?(value)
            s = value.to_s.strip
            return false if s.empty?
            return false unless s.match?(/\A[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z/)

            parts = s.split("-")
            primary = parts.shift.to_s
            return false unless primary.match?(/\A[A-Za-z]{2,8}\z/)

            idx = 0

            idx += 1 if parts[idx]&.match?(/\A[A-Za-z]{4}\z/)
            idx += 1 if parts[idx]&.match?(/\A(?:[A-Za-z]{2}|\d{3})\z/)

            while parts[idx] && (parts[idx].match?(/\A\d[A-Za-z0-9]{3}\z/) || parts[idx].match?(/\A[A-Za-z0-9]{5,8}\z/))
              idx += 1
            end

            while parts[idx] && parts[idx].match?(/\A[0-9A-WY-Za-wy-z]\z/)
              idx += 1
              return false unless parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{2,8}\z/)

              idx += 1
              idx += 1 while parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{2,8}\z/)
            end

            if parts[idx]&.match?(/\A[xX]\z/)
              idx += 1
              return false unless parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{1,8}\z/)

              idx += 1
              idx += 1 while parts[idx] && parts[idx].match?(/\A[A-Za-z0-9]{1,8}\z/)
            end

            idx == parts.length
          rescue StandardError
            false
          end
          private_class_method :bcp47_valid?

          def rebuild_attrs(pairs, code:)
            base = Array(pairs)
            return "" if base.empty? && code.to_s.strip.empty?

            out = []
            seen_code = false

            base.each do |key, value|
              key_s = key.to_s
              next if key_s.strip.empty?

              if key_s.strip.downcase == "code"
                code_str = code.to_s.strip
                if code_str.empty?
                  out << "#{key_s}=#{value}"
                else
                  out << %(code="#{code_str}")
                  seen_code = true
                end
              else
                out << "#{key_s}=#{value}"
              end
            end

            code_str = code.to_s.strip
            out << %(code="#{code_str}") if !code_str.empty? && !seen_code

            " " + out.join(" ")
          rescue StandardError
            code_str = code.to_s.strip
            code_str.empty? ? "" : %( code="#{code_str}")
          end
          private_class_method :rebuild_attrs

          def parse_attrs(raw_attrs)
            s = raw_attrs.to_s
            return [] if s.strip.empty?

            s.scan(/([a-zA-Z0-9_:-]+)\s*=\s*(".*?"|'.*?'|[^\s>]+)/m).map do |k, v|
              [k.to_s, v.to_s]
            end
          rescue StandardError
            []
          end
          private_class_method :parse_attrs
        end
      end
    end
  end
end
