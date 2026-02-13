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
      when :image then ImageContent.new(source: h[:source], media_type: h[:media_type])
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

  # Image content block.
  class ImageContent
    attr_reader :source, :media_type

    def initialize(source:, media_type: nil)
      @source = source.freeze
      @media_type = media_type
    end

    def type = :image

    def to_h
      h = { type: :image, source: source }
      h[:media_type] = media_type if media_type
      h
    end

    def ==(other)
      other.is_a?(ImageContent) && source == other.source
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
