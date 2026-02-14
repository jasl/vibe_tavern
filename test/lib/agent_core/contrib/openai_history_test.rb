# frozen_string_literal: true

require "test_helper"

class AgentCoreContribOpenAIHistoryTest < ActiveSupport::TestCase
  test "coerce_messages accepts AgentCore::Message instances" do
    msg = AgentCore::Message.new(role: :user, content: "hi")
    out = AgentCore::Contrib::OpenAIHistory.coerce_messages([msg])

    assert_equal 1, out.size
    assert_same msg, out.first
  end

  test "coerce_messages maps role=tool to :tool_result" do
    out =
      AgentCore::Contrib::OpenAIHistory.coerce_messages(
        [
          {
            "role" => "tool",
            "content" => "ok",
            "tool_call_id" => "tc_1",
            "name" => "read",
          },
        ],
      )

    msg = out.first
    assert msg.tool_result?
    assert_equal "tc_1", msg.tool_call_id
    assert_equal "read", msg.name
    assert_equal "ok", msg.text
  end

  test "coerce_messages accepts hash messages with string keys" do
    out =
      AgentCore::Contrib::OpenAIHistory.coerce_messages(
        [
          { "role" => "assistant", "content" => "hello" },
        ],
      )

    assert_equal :assistant, out.first.role
    assert_equal "hello", out.first.text
  end

  test "coerce_messages best-effort parses AgentCore-style tool_calls" do
    out =
      AgentCore::Contrib::OpenAIHistory.coerce_messages(
        [
          {
            role: "assistant",
            content: "x",
            tool_calls: [
              { id: "tc_1", name: "echo", arguments: { text: "hi" } },
            ],
          },
        ],
      )

    msg = out.first
    assert msg.has_tool_calls?
    tc = msg.tool_calls.first
    assert_equal "echo", tc.name
    assert_equal({ "text" => "hi" }, tc.arguments)
  end

  test "coerce_messages best-effort parses OpenAI-style tool_calls.function.arguments JSON string" do
    out =
      AgentCore::Contrib::OpenAIHistory.coerce_messages(
        [
          {
            role: "assistant",
            content: "x",
            tool_calls: [
              {
                "id" => "call_1",
                "type" => "function",
                "function" => {
                  "name" => "echo",
                  "arguments" => "{\"text\":\"hi\"}",
                },
              },
            ],
          },
        ],
      )

    tc = out.first.tool_calls.first
    assert_equal "call_1", tc.id
    assert_equal "echo", tc.name
    assert_equal({ "text" => "hi" }, tc.arguments)
    assert tc.arguments_valid?
  end
end
