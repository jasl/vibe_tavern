# frozen_string_literal: true

module AgentCore
  module Utils
    module_function

    DEFAULT_MAX_TOOL_ARGS_BYTES = 200_000
    DEFAULT_MAX_TOOL_OUTPUT_BYTES = 200_000

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
    #
    # String keys take precedence over their non-String equivalents.
    def deep_stringify_keys(value)
      case value
      when Array
        value.map { |v| deep_stringify_keys(v) }
      when Hash
        out = {}

        # Prefer string keys when both exist (e.g., "text" and :text).
        value.each do |k, v|
          out[k] = deep_stringify_keys(v) if k.is_a?(String)
        end

        value.each do |k, v|
          next if k.is_a?(String)

          key = k.to_s
          out[key] = deep_stringify_keys(v) unless out.key?(key)
        end

        out
      else
        value
      end
    end

    def truncate_utf8_bytes(value, max_bytes:)
      max_bytes = Integer(max_bytes)
      return "" if max_bytes <= 0

      str = normalize_utf8(value)
      return str if str.bytesize <= max_bytes

      sliced = str.byteslice(0, max_bytes).to_s
      sliced = sliced.dup.force_encoding(Encoding::UTF_8)

      while !sliced.valid_encoding? && sliced.bytesize.positive?
        sliced = sliced.byteslice(0, sliced.bytesize - 1).to_s
        sliced.force_encoding(Encoding::UTF_8)
      end

      sliced.valid_encoding? ? sliced : ""
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
    private_class_method :normalize_utf8

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

    # Normalize an MCP tool definition hash to AgentCore conventions.
    #
    # MCP uses JSON (string keys) and may use camelCase fields (e.g., inputSchema).
    # This helper normalizes to symbol keys and snake_case for AgentCore internals.
    #
    # @param value [Hash, nil]
    # @return [Hash, nil] { name:, description:, input_schema: }
    def normalize_mcp_tool_definition(value)
      return nil if value.nil?
      raise ArgumentError, "Expected Hash, got #{value.class}" unless value.is_a?(Hash)

      name = value.fetch("name", "").to_s.strip
      return nil if name.empty?

      description = value.fetch("description", "").to_s
      input_schema = value.fetch("inputSchema", value.fetch("input_schema", value.fetch("parameters", {})))
      input_schema = {} unless input_schema.is_a?(Hash)

      { name: name, description: description, input_schema: input_schema }
    end

    # Normalize an MCP tools/call result hash to AgentCore conventions.
    #
    # MCP uses "isError"; AgentCore uses "error".
    #
    # @param value [Hash, nil]
    # @return [Hash] { content:, error:, metadata: }
    def normalize_mcp_tool_call_result(value)
      unless value.is_a?(Hash)
        return { content: [{ type: :text, text: value.to_s }], error: false, metadata: {} }
      end

      content = value.fetch("content", value.fetch(:content, nil))
      content = [{ type: :text, text: value.to_s }] unless content.is_a?(Array)
      content = normalize_mcp_tool_call_content(content)

      error =
        if value.key?("isError")
          value.fetch("isError")
        elsif value.key?(:isError)
          value.fetch(:isError)
        elsif value.key?("is_error")
          value.fetch("is_error")
        elsif value.key?(:is_error)
          value.fetch(:is_error)
        elsif value.key?("error")
          value.fetch("error")
        else
          value.fetch(:error, false)
        end

      structured_content =
        value.fetch("structuredContent",
                    value.fetch(:structuredContent,
                                value.fetch("structured_content",
                                            value.fetch(:structured_content, nil))))

      metadata = {}
      metadata[:structured_content] = structured_content unless structured_content.nil?

      { content: content, error: !!error, metadata: metadata }
    end

    def normalize_mcp_tool_call_content(blocks)
      Array(blocks).map do |block|
        normalize_mcp_tool_call_block(block)
      end
    end
    private_class_method :normalize_mcp_tool_call_content

    def normalize_mcp_tool_call_block(block)
      unless block.is_a?(Hash)
        return { type: :text, text: block.to_s }
      end

      type = block.fetch("type", block.fetch(:type, nil)).to_s.strip

      case type
      when "text"
        text = block.fetch("text", block.fetch(:text, "")).to_s
        annotations = block.fetch("annotations", block.fetch(:annotations, nil))

        out = { type: :text, text: text }
        out[:annotations] = annotations if annotations
        out
      when "image"
        data = block.fetch("data", block.fetch(:data, nil)).to_s
        mime_type = block.fetch("mime_type", block.fetch(:mime_type, block.fetch("mimeType", block.fetch(:mimeType, nil))))
        media_type = normalize_mime_type(mime_type)
        annotations = block.fetch("annotations", block.fetch(:annotations, nil))

        if data.strip.empty? || media_type.nil?
          { type: :text, text: block.to_s }
        else
          out = { type: :image, source_type: :base64, data: data, media_type: media_type }
          out[:annotations] = annotations if annotations
          out
        end
      else
        { type: :text, text: block.to_s }
      end
    rescue StandardError
      { type: :text, text: block.to_s }
    end
    private_class_method :normalize_mcp_tool_call_block

    def normalize_json_schema(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), out|
          next if k.to_s == "required" && v.is_a?(Array) && v.empty?

          out[k] = normalize_json_schema(v)
        end
      when Array
        value.map { |v| normalize_json_schema(v) }
      else
        value
      end
    end

    def normalize_tool_call_id(value, used:, fallback:)
      base_id = value.to_s.strip
      base_id = fallback.to_s if base_id.empty?
      base_id = "tc_1" if base_id.strip.empty?

      id = base_id
      n = 2
      while used.key?(id)
        id = "#{base_id}__#{n}"
        n += 1
      end

      used[id] = true
      id
    end

    def parse_tool_arguments(value, max_bytes: DEFAULT_MAX_TOOL_ARGS_BYTES)
      max_bytes = Integer(max_bytes)
      raise ArgumentError, "max_bytes must be positive" if max_bytes <= 0

      return [{}, nil] if value.nil?

      require "json"

      if value.is_a?(Hash) || value.is_a?(Array)
        normalized = deep_stringify_keys(value)

        begin
          json = JSON.generate(normalized)
        rescue StandardError
          return [{}, :invalid_json]
        end

        return [{}, :too_large] if json.bytesize > max_bytes

        return [normalized, nil] if normalized.is_a?(Hash)

        return [{}, :invalid_json]
      end

      str = normalize_tool_arguments_string(value.to_s)
      return [{}, nil] if str.empty?
      return [{}, :too_large] if str.bytesize > max_bytes

      parsed = JSON.parse(str)
      if parsed.is_a?(String)
        inner = parsed.strip
        return [{}, :too_large] if inner.bytesize > max_bytes

        begin
          parsed2 = JSON.parse(inner)
          parsed = parsed2 unless parsed2.nil?
        rescue JSON::ParserError
          return [{}, :invalid_json]
        end
      end

      return [deep_stringify_keys(parsed), nil] if parsed.is_a?(Hash)

      [{}, :invalid_json]
    rescue JSON::ParserError
      [{}, :invalid_json]
    end

    def normalize_tool_arguments_string(value)
      str = value.to_s.strip
      return str if str.empty?

      fenced = str.match(/\A```(?:json)?\s*(.*?)\s*```\z/mi)
      return str unless fenced

      fenced[1].to_s.strip
    end
    private_class_method :normalize_tool_arguments_string
  end
end
