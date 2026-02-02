# frozen_string_literal: true

module TavernKit
  module Utils
    module_function

    # Convert a string to snake_case (best-effort, ActiveSupport-free).
    #
    # Examples:
    # - "matchPersonaDescription" -> "match_persona_description"
    # - "use_probability" -> "use_probability"
    # - "My::ModuleName" -> "my/module_name"
    def underscore(value)
      word = value.to_s.dup
      return "" if word.empty?

      word.gsub!("::", "/")
      word.gsub!(/([A-Z\d]+)([A-Z][a-z])/, "\\1_\\2")
      word.gsub!(/([a-z\d])([A-Z])/, "\\1_\\2")
      word.tr!("-", "_")
      word.downcase!
      word
    end

    # Convert snake_case (or similar) to lowerCamelCase (best-effort).
    #
    # Examples:
    # - "use_probability" -> "useProbability"
    def camelize_lower(value)
      parts = underscore(value).split("_")
      return "" if parts.empty?

      head = parts.shift.to_s
      head + parts.map { |p| p.capitalize }.join
    end

    # Deep-convert keys to symbols.
    def deep_symbolize_keys(value)
      case value
      when Array then value.map { |v| deep_symbolize_keys(v) }
      when Hash
        value.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
              .transform_values { |v| deep_symbolize_keys(v) }
      else value
      end
    end

    # Deep-convert keys to strings.
    def deep_stringify_keys(value)
      case value
      when Array then value.map { |v| deep_stringify_keys(v) }
      when Hash
        value.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
      else value
      end
    end

    # Returns nil if value is blank, otherwise returns the value.
    def presence(value)
      str = value.to_s.strip
      str.empty? ? nil : value
    end

    # Format a string with {0}, {1}, ... placeholders.
    def string_format(format, *args)
      format.to_s.gsub(/\{(\d+)\}/) do |match|
        idx = Regexp.last_match(1).to_i
        args[idx]&.to_s || match
      end
    end

    # Flexible hash accessor for parsing mixed-key hashes (string/symbol, camelCase/snake_case).
    class HashAccessor
      TRUE_STRINGS = %w[1 true yes y on].freeze

      def self.wrap(hash)
        new(hash)
      end

      def initialize(hash)
        @hash = hash.is_a?(Hash) ? hash : {}
        @candidate_cache = {}
      end

      def valid?
        !@hash.empty?
      end

      # Fetch value by trying multiple keys (string and symbol variants).
      def [](*keys)
        keys.each do |key|
          candidate_keys(key).each do |k|
            return @hash[k] if @hash.key?(k)
          end
        end
        nil
      end

      def fetch(*keys, default: nil)
        self[*keys] || default
      end

      def dig(*path)
        current = @hash
        path.each do |key|
          return nil unless current.is_a?(Hash)

          found = nil
          candidate_keys(key).each do |k|
            if current.key?(k)
              found = current[k]
              break
            end
          end

          current = found
        end
        current
      end

      def bool(*keys, ext_key: nil, default: false)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        to_bool(val, default)
      end

      def int(*keys, ext_key: nil, default: 0)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        return default if val.nil? || val == true || val == false

        val.to_i
      end

      def positive_int(*keys, ext_key: nil)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        return nil if val.nil? || val == true || val == false

        i = val.to_i
        i.positive? ? i : nil
      end

      def str(*keys, ext_key: nil, default: nil)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        val.nil? ? default : val.to_s
      end

      def presence(*keys, ext_key: nil)
        val = str(*keys, ext_key: ext_key)
        val && !val.strip.empty? ? val : nil
      end

      private

      def candidate_keys(key)
        base = key.to_s
        @candidate_cache[base] ||= begin
          underscore = Utils.underscore(base)
          camel = Utils.camelize_lower(base)

          variants = [base, underscore, camel].uniq

          # Hashes coming from JSON parsing are typically string-keyed, but we also
          # accept symbol keys for ergonomics.
          variants.flat_map { |v| [v, v.to_sym] }
        end
      end

      def to_bool(val, default)
        return default if val.nil?
        return val if val == true || val == false

        TRUE_STRINGS.include?(val.to_s.strip.downcase) || default
      end
    end
  end
end
