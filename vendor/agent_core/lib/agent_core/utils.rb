# frozen_string_literal: true

module AgentCore
  module Utils
    module_function

    # Shallow-convert Hash keys to Symbols.
    #
    # Symbol keys take precedence over their String equivalents.
    #
    # @param value [Hash, nil]
    # @return [Hash]
    def symbolize_keys(value)
      return {} if value.nil?
      raise ArgumentError, "Expected Hash, got #{value.class}" unless value.is_a?(Hash)

      out = {}

      # Prefer symbol keys when both exist (e.g., :model and "model").
      value.each do |k, v|
        out[k] = v if k.is_a?(Symbol)
      end

      value.each do |k, v|
        next if k.is_a?(Symbol)

        if k.respond_to?(:to_sym)
          sym = k.to_sym
          out[sym] = v unless out.key?(sym)
        else
          out[k] = v
        end
      end

      out
    end

    # Normalize a MIME type string (lowercase, strip parameters).
    #
    # @param value [String, nil]
    # @return [String, nil]
    def normalize_mime_type(value)
      s = value.to_s.strip
      return nil if s.empty?

      base = s.split(";", 2).first.to_s.strip.downcase
      base.empty? ? nil : base
    end

    # Infer MIME type from a filename using Marcel (if available).
    #
    # Returns nil when inference falls back to "application/octet-stream".
    #
    # @param name [String, nil]
    # @param declared_type [String, nil]
    # @return [String, nil]
    def infer_mime_type(name, declared_type: nil)
      n = name.to_s.strip
      declared = normalize_mime_type(declared_type)

      return declared if n.empty? && declared
      return nil if n.empty? && declared.nil?

      require "marcel"
      inferred = Marcel::MimeType.for(name: n, declared_type: declared)
      normalized = normalize_mime_type(inferred)
      normalized == "application/octet-stream" ? nil : normalized
    end

    # Assert that all keys in a Hash are Symbols.
    #
    # Raises ArgumentError if any key is not a Symbol. Used to enforce
    # the symbol-keys convention at API boundaries.
    #
    # @param value [Hash]
    # @param path [String] Human-readable context for error messages
    # @return [nil]
    def assert_symbol_keys!(value, path: "value")
      raise ArgumentError, "#{path} must be a Hash" unless value.is_a?(Hash)

      value.each_key do |key|
        unless key.is_a?(Symbol)
          raise ArgumentError, "#{path} keys must be Symbols (got #{key.class})"
        end
      end

      nil
    end

    # Extract a filename from a URL (best-effort).
    #
    # @param url [String, nil]
    # @return [String, nil]
    def filename_from_url(url)
      return nil if url.nil? || url.to_s.strip.empty?

      require "uri"
      uri = URI.parse(url.to_s)
      path = uri.path.to_s
      base = File.basename(path)
      base.empty? ? nil : base
    rescue URI::InvalidURIError
      nil
    end
  end
end
