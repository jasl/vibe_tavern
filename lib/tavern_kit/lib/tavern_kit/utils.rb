# frozen_string_literal: true

module TavernKit
  module Utils
    module_function

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
      end

      def valid?
        !@hash.empty?
      end

      # Fetch value by trying multiple keys (string and symbol variants).
      def [](*keys)
        keys.each do |key|
          [key.to_s, key.to_sym].each do |k|
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
          current = current[key.to_s] || current[key.to_sym]
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
        val.nil? ? default : val.to_i
      end

      def positive_int(*keys, ext_key: nil)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        return nil if val.nil?

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

      def to_bool(val, default)
        return default if val.nil?
        return val if val == true || val == false

        TRUE_STRINGS.include?(val.to_s.strip.downcase) || default
      end
    end
  end
end
