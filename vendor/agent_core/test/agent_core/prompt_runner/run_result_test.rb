# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptRunner::RunResultTest < Minitest::Test
  def build_result(messages:, final_message:, turns:, **kwargs)
    now = Time.now

    AgentCore::PromptRunner::RunResult.new(
      run_id: "run_1",
      started_at: now,
      ended_at: now,
      duration_ms: 0.0,
      messages: messages,
      final_message: final_message,
      turns: turns,
      **kwargs
    )
  end

  def test_basic_attributes
    msg = AgentCore::Message.new(role: :assistant, content: "Hello")
    result = build_result(
      messages: [msg],
      final_message: msg,
      turns: 1,
      stop_reason: :end_turn,
    )

    assert_equal [msg], result.messages
    assert_same msg, result.final_message
    assert_equal 1, result.turns
    assert_equal :end_turn, result.stop_reason
  end

  def test_text_delegates_to_final_message
    msg = AgentCore::Message.new(role: :assistant, content: "Reply text")
    result = build_result(
      messages: [msg], final_message: msg, turns: 1,
    )

    assert_equal "Reply text", result.text
  end

  def test_text_with_nil_final_message
    result = build_result(
      messages: [], final_message: nil, turns: 0,
    )

    assert_nil result.text
  end

  def test_used_tools_true
    msg = AgentCore::Message.new(role: :assistant, content: "done")
    result = build_result(
      messages: [msg], final_message: msg, turns: 2,
      tool_calls_made: [{ name: "read", arguments: {} }],
    )

    assert result.used_tools?
  end

  def test_used_tools_false
    msg = AgentCore::Message.new(role: :assistant, content: "done")
    result = build_result(
      messages: [msg], final_message: msg, turns: 1,
    )

    refute result.used_tools?
  end

  def test_max_turns_reached
    msg = AgentCore::Message.new(role: :assistant, content: "done")
    result = build_result(
      messages: [msg], final_message: msg, turns: 10,
      stop_reason: :max_turns,
    )

    assert result.max_turns_reached?
  end

  def test_max_turns_not_reached
    msg = AgentCore::Message.new(role: :assistant, content: "done")
    result = build_result(
      messages: [msg], final_message: msg, turns: 1,
      stop_reason: :end_turn,
    )

    refute result.max_turns_reached?
  end

  def test_usage_and_per_turn_usage
    usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 100, output_tokens: 50)
    per_turn = [usage]
    msg = AgentCore::Message.new(role: :assistant, content: "hi")

    result = build_result(
      messages: [msg], final_message: msg, turns: 1,
      usage: usage, per_turn_usage: per_turn,
    )

    assert_same usage, result.usage
    assert_equal [usage], result.per_turn_usage
  end

  def test_messages_frozen
    msg = AgentCore::Message.new(role: :assistant, content: "hi")
    result = build_result(
      messages: [msg], final_message: msg, turns: 1,
    )

    assert result.messages.frozen?
    assert result.tool_calls_made.frozen?
  end
end
