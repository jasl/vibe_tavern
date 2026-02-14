# frozen_string_literal: true

module AgentCore
  # Unified message format used throughout AgentCore.
  #
  # Follows Anthropic-style content blocks for maximum expressiveness.
  # Can be converted to OpenAI format when needed by providers.
  #
  # @example Simple text message
  #   Message.new(role: :user, content: "Hello!")
  #
  # @example Assistant message with tool calls
  #   Message.new(
  #     role: :assistant,
  #     content: [TextContent.new(text: "Let me check that.")],
  #     tool_calls: [ToolCall.new(id: "tc_1", name: "read", arguments: { path: "config.json" })]
  #   )
  class Message
    ROLES = %i[system user assistant tool_result].freeze

    attr_reader :role, :content, :tool_calls, :tool_call_id, :name, :metadata

    def initialize(role:, content:, tool_calls: nil, tool_call_id: nil, name: nil, metadata: nil)
      @role = validate_role!(role)
      @content = content.freeze
      @tool_calls = tool_calls&.freeze
      @tool_call_id = tool_call_id
      @name = name
      @metadata = (metadata || {}).freeze
    end

    def system? = role == :system
    def user? = role == :user
    def assistant? = role == :assistant
    def tool_result? = role == :tool_result

    # Returns text content as a single string.
    # For array content, concatenates all TextContent blocks.
    def text
      case content
      when String
        content
      when Array
        content.filter_map { |block| block.text if block.respond_to?(:text) }.join
      else
        content.to_s
      end
    end

    # Whether this assistant message contains tool calls.
    def has_tool_calls?
      tool_calls && !tool_calls.empty?
    end

    # Convert to a plain Hash for serialization.
    def to_h
      h = { role: role, content: serialize_content }
      h[:tool_calls] = tool_calls.map(&:to_h) if has_tool_calls?
      h[:tool_call_id] = tool_call_id if tool_call_id
      h[:name] = name if name
      h[:metadata] = metadata unless metadata.empty?
      h
    end

    def ==(other)
      other.is_a?(Message) &&
        role == other.role &&
        content == other.content &&
        tool_calls == other.tool_calls &&
        tool_call_id == other.tool_call_id
    end

    # Build a Message from a serialized Hash.
    def self.from_h(hash)
      h = hash.transform_keys(&:to_sym)
      content = deserialize_content(h[:content])
      tool_calls = h[:tool_calls]&.map { |tc| ToolCall.from_h(tc) }

      new(
        role: h[:role],
        content: content,
        tool_calls: tool_calls,
        tool_call_id: h[:tool_call_id],
        name: h[:name],
        metadata: h[:metadata]
      )
    end

    private

    def validate_role!(role)
      raise ArgumentError, "Role cannot be nil. Must be one of: #{ROLES.join(", ")}" if role.nil?

      sym = role.to_sym
      unless ROLES.include?(sym)
        raise ArgumentError, "Invalid role: #{role}. Must be one of: #{ROLES.join(", ")}"
      end
      sym
    end

    def serialize_content
      case content
      when String
        content
      when Array
        content.map(&:to_h)
      else
        content.to_s
      end
    end

    def self.deserialize_content(content)
      case content
      when String
        content
      when Array
        content.map { |block| ContentBlock.from_h(block) }
      else
        content.to_s
      end
    end
  end

  # A tool call requested by the assistant.
  class ToolCall
    attr_reader :id, :name, :arguments

    def initialize(id:, name:, arguments:)
      @id = id
      @name = name
      @arguments = (arguments || {}).freeze
    end

    def to_h
      { id: id, name: name, arguments: arguments }
    end

    def ==(other)
      other.is_a?(ToolCall) && id == other.id && name == other.name && arguments == other.arguments
    end

    def self.from_h(hash)
      h = hash.transform_keys(&:to_sym)
      new(id: h[:id], name: h[:name], arguments: h[:arguments] || {})
    end
  end

  # Base module for content blocks.
  module ContentBlock
    def self.from_h(hash)
      h = hash.transform_keys(&:to_sym)
      case h[:type]&.to_sym
      when :text then TextContent.new(text: h[:text])
      when :image then ImageContent.from_h(h)
      when :document then DocumentContent.from_h(h)
      when :audio then AudioContent.from_h(h)
      when :tool_use then ToolUseContent.new(id: h[:id], name: h[:name], input: h[:input])
      when :tool_result then ToolResultContent.new(tool_use_id: h[:tool_use_id], content: h[:content], is_error: h[:is_error])
      else
        TextContent.new(text: h[:text] || h.to_s)
      end
    end
  end

  # Text content block.
  class TextContent
    attr_reader :text

    def initialize(text:)
      @text = text
    end

    def type = :text

    def to_h
      { type: :text, text: text }
    end

    def ==(other)
      other.is_a?(TextContent) && text == other.text
    end
  end

  # Shared validation logic for media content blocks (image, document, audio).
  #
  # Provides source_type-based validation:
  #   :base64 — requires data + media_type
  #   :url    — requires url
  module MediaSourceValidation
    VALID_SOURCE_TYPES = %i[base64 url].freeze

    private

    def validate_media_source!
      cfg = AgentCore.config

      raise ArgumentError, "source_type is required" if source_type.nil?
      unless VALID_SOURCE_TYPES.include?(source_type)
        raise ArgumentError, "source_type must be one of: #{VALID_SOURCE_TYPES.join(", ")} (got #{source_type.inspect})"
      end

      case source_type
      when :base64
        raise ArgumentError, "data is required for base64 source" if data.nil? || data.empty?
        raise ArgumentError, "media_type is required for base64 source" if media_type.nil? || media_type.empty?
      when :url
        raise ArgumentError, "url sources are disabled" unless cfg.allow_url_media_sources
        raise ArgumentError, "url is required for url source" if url.nil? || url.empty?

        if (allowed_schemes = cfg.allowed_media_url_schemes)
          allowed = Array(allowed_schemes).map(&:to_s).map(&:downcase)
          require "uri"
          uri = begin
            URI.parse(url.to_s)
          rescue URI::InvalidURIError => e
            raise ArgumentError, "url is invalid: #{e.message}"
          end
          scheme = uri.scheme&.downcase
          unless scheme && allowed.include?(scheme)
            raise ArgumentError, "url scheme must be one of: #{allowed.join(", ")} (got #{scheme.inspect})"
          end
        end
      end

      if (validator = cfg.media_source_validator)
        allowed = validator.call(self)
        raise ArgumentError, "media source rejected by policy" unless allowed
      end
    end
  end

  # Image content block.
  #
  # Supports both base64-encoded data and URL references.
  # Provider layer converts to API-specific format (Anthropic, OpenAI, Google).
  #
  # @example Base64 image
  #   ImageContent.new(source_type: :base64, media_type: "image/png", data: "iVBOR...")
  #
  # @example URL image
  #   ImageContent.new(source_type: :url, url: "https://example.com/photo.jpg")
  class ImageContent
    include MediaSourceValidation

    attr_reader :source_type, :data, :media_type, :url

    def initialize(source_type:, data: nil, media_type: nil, url: nil)
      @source_type = source_type&.to_sym
      @data = data.is_a?(String) ? data.dup.freeze : data
      @media_type = Utils.normalize_mime_type(media_type)&.freeze
      @url = url.is_a?(String) ? url.dup.freeze : url
      validate_media_source!
    end

    def type = :image

    def effective_media_type
      media_type || Utils.infer_mime_type(Utils.filename_from_url(url))
    end

    def to_h
      h = { type: :image, source_type: source_type }
      h[:data] = data if data
      h[:media_type] = media_type if media_type
      h[:url] = url if url
      h
    end

    def ==(other)
      other.is_a?(ImageContent) &&
        source_type == other.source_type &&
        data == other.data &&
        url == other.url &&
        media_type == other.media_type
    end

    def self.from_h(hash)
      h = hash.transform_keys(&:to_sym)
      new(
        source_type: h[:source_type],
        data: h[:data],
        media_type: h[:media_type],
        url: h[:url]
      )
    end
  end

  # Document content block (PDF, plain text, HTML, CSV, etc.).
  #
  # Provider layer converts to API-specific format. For providers that
  # don't support documents natively, the app can extract text first.
  #
  # @example Base64 PDF
  #   DocumentContent.new(source_type: :base64, media_type: "application/pdf", data: "JVBERi...", filename: "report.pdf")
  #
  # @example URL document
  #   DocumentContent.new(source_type: :url, url: "https://example.com/doc.pdf", media_type: "application/pdf")
  class DocumentContent
    include MediaSourceValidation

    # Text-based MIME types where data can be counted as text tokens.
    TEXT_MEDIA_TYPES = %w[text/plain text/html text/csv text/markdown].freeze

    attr_reader :source_type, :data, :media_type, :url, :filename, :title

    def initialize(source_type:, data: nil, media_type: nil, url: nil, filename: nil, title: nil)
      @source_type = source_type&.to_sym
      @data = data.is_a?(String) ? data.dup.freeze : data
      @media_type = Utils.normalize_mime_type(media_type)&.freeze
      @url = url.is_a?(String) ? url.dup.freeze : url
      @filename = filename.is_a?(String) ? filename.dup.freeze : filename
      @title = title.is_a?(String) ? title.dup.freeze : title
      validate_media_source!
    end

    def type = :document

    def effective_media_type
      media_type || Utils.infer_mime_type(filename || Utils.filename_from_url(url))
    end

    # Whether the document's media_type is a text-based format.
    def text_based?
      TEXT_MEDIA_TYPES.include?(effective_media_type)
    end

    # Returns text content for text-based documents (as provided in data), nil otherwise.
    def text
      return nil unless text_based? && source_type == :base64 && data
      data
    end

    def to_h
      h = { type: :document, source_type: source_type }
      h[:data] = data if data
      h[:media_type] = media_type if media_type
      h[:url] = url if url
      h[:filename] = filename if filename
      h[:title] = title if title
      h
    end

    def ==(other)
      other.is_a?(DocumentContent) &&
        source_type == other.source_type &&
        data == other.data &&
        url == other.url &&
        media_type == other.media_type
    end

    def self.from_h(hash)
      h = hash.transform_keys(&:to_sym)
      new(
        source_type: h[:source_type],
        data: h[:data],
        media_type: h[:media_type],
        url: h[:url],
        filename: h[:filename],
        title: h[:title]
      )
    end
  end

  # Audio content block.
  #
  # Supports base64-encoded audio and URL references.
  # Optional transcript for providers that don't support native audio input.
  #
  # @example Base64 audio with transcript
  #   AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "UklGR...", transcript: "Hello world")
  class AudioContent
    include MediaSourceValidation

    attr_reader :source_type, :data, :media_type, :url, :transcript

    def initialize(source_type:, data: nil, media_type: nil, url: nil, transcript: nil)
      @source_type = source_type&.to_sym
      @data = data.is_a?(String) ? data.dup.freeze : data
      @media_type = Utils.normalize_mime_type(media_type)&.freeze
      @url = url.is_a?(String) ? url.dup.freeze : url
      @transcript = transcript.is_a?(String) ? transcript.dup.freeze : transcript
      validate_media_source!
    end

    def type = :audio

    def effective_media_type
      media_type || Utils.infer_mime_type(Utils.filename_from_url(url))
    end

    # Returns transcript text (for token counting and fallback rendering).
    def text
      transcript
    end

    def to_h
      h = { type: :audio, source_type: source_type }
      h[:data] = data if data
      h[:media_type] = media_type if media_type
      h[:url] = url if url
      h[:transcript] = transcript if transcript
      h
    end

    def ==(other)
      other.is_a?(AudioContent) &&
        source_type == other.source_type &&
        data == other.data &&
        url == other.url &&
        media_type == other.media_type &&
        transcript == other.transcript
    end

    def self.from_h(hash)
      h = hash.transform_keys(&:to_sym)
      new(
        source_type: h[:source_type],
        data: h[:data],
        media_type: h[:media_type],
        url: h[:url],
        transcript: h[:transcript]
      )
    end
  end

  # Tool use content block (in assistant messages).
  class ToolUseContent
    attr_reader :id, :name, :input

    def initialize(id:, name:, input:)
      @id = id
      @name = name
      @input = (input || {}).freeze
    end

    def type = :tool_use

    def to_h
      { type: :tool_use, id: id, name: name, input: input }
    end

    def ==(other)
      other.is_a?(ToolUseContent) && id == other.id && name == other.name
    end
  end

  # Tool result content block.
  class ToolResultContent
    attr_reader :tool_use_id, :content, :is_error

    def initialize(tool_use_id:, content:, is_error: false)
      @tool_use_id = tool_use_id
      @content = content
      @is_error = is_error
    end

    def type = :tool_result
    def error? = is_error

    def to_h
      { type: :tool_result, tool_use_id: tool_use_id, content: content, is_error: is_error }
    end

    def ==(other)
      other.is_a?(ToolResultContent) && tool_use_id == other.tool_use_id
    end
  end
end
