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
      when Array
        value.map { |v| deep_symbolize_keys(v) }
      when Hash
        value.each_with_object({}) do |(k, v), out|
          if k.is_a?(Symbol)
            out[k] = deep_symbolize_keys(v)
          elsif k.respond_to?(:to_sym)
            sym = k.to_sym
            out[sym] = deep_symbolize_keys(v) unless out.key?(sym)
          else
            out[k] = deep_symbolize_keys(v)
          end
        end
      else
        value
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

    # Deep-merge two hashes.
    #
    # Hash values are merged recursively. Arrays and scalar values are replaced by
    # the right-hand side.
    def deep_merge_hashes(left, right)
      lhs = left.is_a?(Hash) ? left : {}
      rhs = right.is_a?(Hash) ? right : {}

      out = lhs.each_with_object({}) { |(k, v), acc| acc[k] = v }

      rhs.each do |key, value|
        if out[key].is_a?(Hash) && value.is_a?(Hash)
          out[key] = deep_merge_hashes(out[key], value)
        else
          out[key] = value
        end
      end

      out
    end

    # Assert that all keys in a nested Hash/Array structure are Symbols.
    #
    # This is intended for programmer-owned configuration hashes.
    def assert_deep_symbol_keys!(value, path: "value")
      case value
      when Hash
        value.each do |k, v|
          unless k.is_a?(Symbol)
            raise ArgumentError, "#{path} keys must be Symbols (got #{k.class})"
          end

          assert_deep_symbol_keys!(v, path: "#{path}.#{k}")
        end
      when Array
        value.each_with_index do |v, idx|
          assert_deep_symbol_keys!(v, path: "#{path}[#{idx}]")
        end
      end

      nil
    end

    # Assert that all keys in a Hash are Symbols.
    #
    # This is intended for programmer-owned top-level configuration hashes.
    def assert_symbol_keys!(value, path: "value")
      raise ArgumentError, "#{path} must be a Hash" unless value.is_a?(Hash)

      value.each_key do |key|
        unless key.is_a?(Symbol)
          raise ArgumentError, "#{path} keys must be Symbols (got #{key.class})"
        end
      end

      nil
    end

    # Normalize a programmer-owned hash value that must have deep Symbol keys.
    #
    # Returns {} when value is nil.
    def normalize_symbol_keyed_hash(value, path:)
      return {} if value.nil?
      raise ArgumentError, "#{path} must be a Hash" unless value.is_a?(Hash)

      assert_deep_symbol_keys!(value, path: path.to_s)
      value
    end

    def normalize_request_overrides(value)
      normalize_symbol_keyed_hash(value, path: "request_overrides")
    end

    # Normalize a string-list-like input into an Array<String> (or nil).
    #
    # Accepts strings, symbols, arrays, etc. Elements are `to_s.strip`'d and
    # empty strings are removed.
    def normalize_string_list(value)
      list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
      list.empty? ? nil : list
    end

    # Returns true when the user explicitly provided an empty string list.
    #
    # - "" / " , " => explicit empty
    # - [] / [" ", ""] => explicit empty
    #
    # Non string/array values return false.
    def explicit_empty_string_list?(value)
      case value
      when String
        value.split(",").map(&:strip).reject(&:empty?).empty?
      when Array
        value.map { |v| v.to_s.strip }.reject(&:empty?).empty?
      else
        false
      end
    end

    # Merge two "string list" values.
    #
    # - nil right-hand side => nil (no override)
    # - explicit empty right-hand side => []
    # - otherwise => unique concatenation
    def merge_string_list(left, right)
      return nil if right.nil?

      right_list = normalize_string_list(right)
      return [] if explicit_empty_string_list?(right)

      left_list = normalize_string_list(left)
      return right_list if left_list.nil?

      (left_list + right_list).uniq
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
      FALSE_STRINGS = %w[0 false no n off].freeze

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
        val = self[*keys]
        val.nil? ? default : val
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

        v = val.to_s.strip.downcase
        return true if TRUE_STRINGS.include?(v)
        return false if FALSE_STRINGS.include?(v)

        default
      end
    end
  end
end
