# frozen_string_literal: true

require "test_helper"

class AgentCore::ErrorsTest < Minitest::Test
  def test_base_error_inherits_standard_error
    assert_operator AgentCore::Error, :<, StandardError
  end

  def test_not_implemented_error
    error = AgentCore::NotImplementedError.new("missing method")
    assert_kind_of AgentCore::Error, error
    assert_equal "missing method", error.message
  end

  def test_configuration_error
    error = AgentCore::ConfigurationError.new("bad config")
    assert_kind_of AgentCore::Error, error
  end

  def test_tool_error_with_attributes
    error = AgentCore::ToolError.new("tool failed", tool_name: "read", tool_call_id: "tc_1")
    assert_equal "tool failed", error.message
    assert_equal "read", error.tool_name
    assert_equal "tc_1", error.tool_call_id
  end

  def test_tool_error_without_attributes
    error = AgentCore::ToolError.new("fail")
    assert_nil error.tool_name
    assert_nil error.tool_call_id
  end

  def test_tool_not_found_error_inherits_tool_error
    error = AgentCore::ToolNotFoundError.new("not found", tool_name: "missing")
    assert_kind_of AgentCore::ToolError, error
    assert_equal "missing", error.tool_name
  end

  def test_tool_denied_error
    error = AgentCore::ToolDeniedError.new("denied", reason: "policy", tool_name: "write")
    assert_kind_of AgentCore::ToolError, error
    assert_equal "policy", error.reason
    assert_equal "write", error.tool_name
  end

  def test_max_turns_exceeded_error
    error = AgentCore::MaxTurnsExceededError.new(turns: 10)
    assert_equal 10, error.turns
    assert_includes error.message, "10"
  end

  def test_max_turns_exceeded_error_custom_message
    error = AgentCore::MaxTurnsExceededError.new("custom msg", turns: 5)
    assert_equal "custom msg", error.message
    assert_equal 5, error.turns
  end

  def test_provider_error
    error = AgentCore::ProviderError.new("api error", status: 429, body: "rate limited")
    assert_kind_of AgentCore::Error, error
    assert_equal 429, error.status
    assert_equal "rate limited", error.body
  end

  def test_context_window_exceeded_error
    error = AgentCore::ContextWindowExceededError.new(
      estimated_tokens: 50_000,
      message_tokens: 40_000,
      tool_tokens: 10_000,
      context_window: 32_000,
      reserved_output: 4_096,
    )
    assert_equal 50_000, error.estimated_tokens
    assert_equal 40_000, error.message_tokens
    assert_equal 10_000, error.tool_tokens
    assert_equal 32_000, error.context_window
    assert_equal 4_096, error.reserved_output
    assert_equal 27_904, error.limit
    assert_includes error.message, "50000"
  end

  def test_context_window_exceeded_error_custom_message
    error = AgentCore::ContextWindowExceededError.new("too big")
    assert_equal "too big", error.message
  end

  def test_stream_error
    assert_operator AgentCore::StreamError, :<, AgentCore::Error
  end

  # MCP errors
  def test_mcp_error_hierarchy
    assert_operator AgentCore::MCP::Error, :<, AgentCore::Error
    assert_operator AgentCore::MCP::TransportError, :<, AgentCore::MCP::Error
    assert_operator AgentCore::MCP::ProtocolError, :<, AgentCore::MCP::Error
    assert_operator AgentCore::MCP::TimeoutError, :<, AgentCore::MCP::Error
    assert_operator AgentCore::MCP::ServerError, :<, AgentCore::MCP::Error
    assert_operator AgentCore::MCP::InitializationError, :<, AgentCore::MCP::Error
    assert_operator AgentCore::MCP::ClosedError, :<, AgentCore::MCP::Error
    assert_operator AgentCore::MCP::ProtocolVersionNotSupportedError, :<, AgentCore::MCP::Error
  end

  def test_json_rpc_error
    error = AgentCore::MCP::JsonRpcError.new(-32600, "Invalid request", data: { detail: "missing id" })
    assert_kind_of AgentCore::MCP::Error, error
    assert_equal(-32600, error.code)
    assert_equal "Invalid request", error.message
    assert_equal({ detail: "missing id" }, error.data)
  end

  def test_json_rpc_error_without_data
    error = AgentCore::MCP::JsonRpcError.new(-32601, "Method not found")
    assert_nil error.data
  end
end
