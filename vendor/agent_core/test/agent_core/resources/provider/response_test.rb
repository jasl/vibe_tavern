# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Provider::ResponseTest < Minitest::Test
  def test_basic_response
    msg = AgentCore::Message.new(role: :assistant, content: "Hello")
    response = AgentCore::Resources::Provider::Response.new(message: msg)

    assert_same msg, response.message
    assert_nil response.usage
    assert_nil response.raw
    assert_equal :end_turn, response.stop_reason
  end

  def test_has_tool_calls_false
    msg = AgentCore::Message.new(role: :assistant, content: "No tools")
    response = AgentCore::Resources::Provider::Response.new(message: msg)

    refute response.has_tool_calls?
  end

  def test_has_tool_calls_true
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: {})
    msg = AgentCore::Message.new(role: :assistant, content: "Using tool", tool_calls: [tc])
    response = AgentCore::Resources::Provider::Response.new(message: msg, stop_reason: :tool_use)

    assert response.has_tool_calls?
    assert_equal [tc], response.tool_calls
    assert response.tool_use?
  end

  def test_tool_calls_with_nil_message
    response = AgentCore::Resources::Provider::Response.new(message: nil)
    assert_equal [], response.tool_calls
  end

  def test_truncated
    msg = AgentCore::Message.new(role: :assistant, content: "Partial...")
    response = AgentCore::Resources::Provider::Response.new(message: msg, stop_reason: :max_tokens)

    assert response.truncated?
    refute response.tool_use?
  end

  def test_with_usage_and_raw
    msg = AgentCore::Message.new(role: :assistant, content: "hi")
    usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 5)
    raw = { id: "msg_123" }

    response = AgentCore::Resources::Provider::Response.new(
      message: msg, usage: usage, raw: raw, stop_reason: :end_turn,
    )

    assert_same usage, response.usage
    assert_equal({ id: "msg_123" }, response.raw)
  end
end

class AgentCore::Resources::Provider::UsageTest < Minitest::Test
  def test_defaults
    usage = AgentCore::Resources::Provider::Usage.new
    assert_equal 0, usage.input_tokens
    assert_equal 0, usage.output_tokens
    assert_equal 0, usage.cache_creation_tokens
    assert_equal 0, usage.cache_read_tokens
  end

  def test_total_tokens
    usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 100, output_tokens: 50)
    assert_equal 150, usage.total_tokens
  end

  def test_to_h
    usage = AgentCore::Resources::Provider::Usage.new(
      input_tokens: 100, output_tokens: 50,
      cache_creation_tokens: 10, cache_read_tokens: 20,
    )
    h = usage.to_h

    assert_equal 100, h[:input_tokens]
    assert_equal 50, h[:output_tokens]
    assert_equal 10, h[:cache_creation_tokens]
    assert_equal 20, h[:cache_read_tokens]
    assert_equal 150, h[:total_tokens]
  end

  def test_addition
    a = AgentCore::Resources::Provider::Usage.new(input_tokens: 100, output_tokens: 50)
    b = AgentCore::Resources::Provider::Usage.new(input_tokens: 200, output_tokens: 30,
                                                   cache_creation_tokens: 5)
    c = a + b

    assert_equal 300, c.input_tokens
    assert_equal 80, c.output_tokens
    assert_equal 5, c.cache_creation_tokens
    assert_equal 0, c.cache_read_tokens
  end
end
