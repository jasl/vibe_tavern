# frozen_string_literal: true

require "test_helper"

class AgentCore::StreamEventTest < Minitest::Test
  def test_text_delta
    event = AgentCore::StreamEvent::TextDelta.new(text: "hello")
    assert_equal "hello", event.text
    assert_equal :text_delta, event.type
  end

  def test_thinking_delta
    event = AgentCore::StreamEvent::ThinkingDelta.new(text: "reasoning...")
    assert_equal "reasoning...", event.text
    assert_equal :thinking_delta, event.type
  end

  def test_tool_call_start
    event = AgentCore::StreamEvent::ToolCallStart.new(id: "tc_1", name: "read")
    assert_equal "tc_1", event.id
    assert_equal "read", event.name
    assert_equal :tool_call_start, event.type
  end

  def test_tool_call_delta
    event = AgentCore::StreamEvent::ToolCallDelta.new(id: "tc_1", arguments_delta: '{"pa')
    assert_equal "tc_1", event.id
    assert_equal '{"pa', event.arguments_delta
    assert_equal :tool_call_delta, event.type
  end

  def test_tool_call_end
    event = AgentCore::StreamEvent::ToolCallEnd.new(id: "tc_1", name: "read", arguments: { path: "f.txt" })
    assert_equal "tc_1", event.id
    assert_equal "read", event.name
    assert_equal({ path: "f.txt" }, event.arguments)
    assert_equal :tool_call_end, event.type
  end

  def test_tool_execution_start
    event = AgentCore::StreamEvent::ToolExecutionStart.new(tool_call_id: "tc_1", name: "read", arguments: {})
    assert_equal "tc_1", event.tool_call_id
    assert_equal "read", event.name
    assert_equal :tool_execution_start, event.type
  end

  def test_tool_execution_update
    event = AgentCore::StreamEvent::ToolExecutionUpdate.new(tool_call_id: "tc_1", partial_result: "partial")
    assert_equal "tc_1", event.tool_call_id
    assert_equal "partial", event.partial_result
    assert_equal :tool_execution_update, event.type
  end

  def test_tool_execution_end
    event = AgentCore::StreamEvent::ToolExecutionEnd.new(
      tool_call_id: "tc_1", name: "read", result: "data", error: false,
    )
    assert_equal "tc_1", event.tool_call_id
    assert_equal "read", event.name
    assert_equal "data", event.result
    refute event.error?
    assert_equal :tool_execution_end, event.type
  end

  def test_tool_execution_end_with_error
    event = AgentCore::StreamEvent::ToolExecutionEnd.new(
      tool_call_id: "tc_1", name: "read", result: "oops", error: true,
    )
    assert event.error?
  end

  def test_turn_start
    event = AgentCore::StreamEvent::TurnStart.new(turn_number: 3)
    assert_equal 3, event.turn_number
    assert_equal :turn_start, event.type
  end

  def test_turn_end
    msg = AgentCore::Message.new(role: :assistant, content: "done")
    event = AgentCore::StreamEvent::TurnEnd.new(turn_number: 3, message: msg)
    assert_equal 3, event.turn_number
    assert_same msg, event.message
    assert_nil event.stop_reason
    assert_nil event.usage
    assert_equal :turn_end, event.type
  end

  def test_turn_end_with_stop_reason_and_usage
    msg = AgentCore::Message.new(role: :assistant, content: "done")
    usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 1, output_tokens: 2)
    event = AgentCore::StreamEvent::TurnEnd.new(turn_number: 1, message: msg, stop_reason: :end_turn, usage: usage)
    assert_equal :end_turn, event.stop_reason
    assert_same usage, event.usage
  end

  def test_message_complete
    msg = AgentCore::Message.new(role: :assistant, content: "hi")
    event = AgentCore::StreamEvent::MessageComplete.new(message: msg)
    assert_same msg, event.message
    assert_equal :message_complete, event.type
  end

  def test_done
    event = AgentCore::StreamEvent::Done.new(stop_reason: :end_turn, usage: { input: 10 })
    assert_equal :end_turn, event.stop_reason
    assert_equal({ input: 10 }, event.usage)
    assert_equal :done, event.type
  end

  def test_done_without_usage
    event = AgentCore::StreamEvent::Done.new(stop_reason: :max_tokens)
    assert_nil event.usage
  end

  def test_error_event
    err = RuntimeError.new("boom")
    event = AgentCore::StreamEvent::ErrorEvent.new(error: err, recoverable: true)
    assert_same err, event.error
    assert event.recoverable?
    assert_equal :error, event.type
  end

  def test_error_event_not_recoverable_by_default
    event = AgentCore::StreamEvent::ErrorEvent.new(error: RuntimeError.new("x"))
    refute event.recoverable?
  end
end
