# frozen_string_literal: true

module AgentCore
  # Base error class for all AgentCore errors.
  class Error < StandardError; end

  # Raised when a required abstract method is not implemented.
  class NotImplementedError < Error; end

  # Raised when configuration is invalid or incomplete.
  class ConfigurationError < Error; end

  # Raised when a tool call fails.
  class ToolError < Error
    attr_reader :tool_name, :tool_call_id

    def initialize(message = nil, tool_name: nil, tool_call_id: nil)
      @tool_name = tool_name
      @tool_call_id = tool_call_id
      super(message)
    end
  end

  # Raised when a tool is not found in the registry.
  class ToolNotFoundError < ToolError; end

  # Raised when tool execution is denied by policy.
  class ToolDeniedError < ToolError
    attr_reader :reason

    def initialize(message = nil, reason: nil, **kwargs)
      @reason = reason
      super(message, **kwargs)
    end
  end

  # Raised when the maximum number of turns is exceeded.
  class MaxTurnsExceededError < Error
    attr_reader :turns

    def initialize(message = nil, turns: nil)
      @turns = turns
      super(message || "Maximum turns exceeded: #{turns}")
    end
  end

  # Raised when an LLM provider returns an error.
  class ProviderError < Error
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      @status = status
      @body = body
      super(message)
    end
  end

  # Raised when the estimated prompt tokens exceed the context window.
  class ContextWindowExceededError < Error
    attr_reader :estimated_tokens, :message_tokens, :tool_tokens, :context_window, :reserved_output, :limit

    def initialize(
      message = nil,
      estimated_tokens: nil,
      message_tokens: nil,
      tool_tokens: nil,
      context_window: nil,
      reserved_output: 0,
      limit: nil
    )
      @estimated_tokens = estimated_tokens
      @message_tokens = message_tokens
      @tool_tokens = tool_tokens
      @context_window = context_window
      @reserved_output = reserved_output
      @limit = limit || (context_window && reserved_output ? context_window - reserved_output : nil)

      super(message || "Estimated #{estimated_tokens} prompt tokens exceeds limit #{self.limit} " \
                        "(messages: #{message_tokens}, tools: #{tool_tokens}, context_window: #{context_window}, reserved_output: #{reserved_output})")
    end
  end

  # Raised when streaming encounters an error.
  class StreamError < Error; end

  # MCP-specific errors
  module MCP
    class Error < AgentCore::Error; end
    class TransportError < Error; end
    class ProtocolError < Error; end
    class TimeoutError < Error; end
    class ServerError < Error; end
    class InitializationError < Error; end
  end
end
