# frozen_string_literal: true

require "test_helper"

class TavernKit::DialectsTest < Minitest::Test
  def test_openai_passthrough_tool_calls_and_tool_call_id
    tool_calls = [
      {
        id: "call_1",
        type: "function",
        function: {
          name: "add",
          arguments: "{\"a\":1,\"b\":2}",
        },
      },
    ]

    messages = [
      TavernKit::Prompt::Message.new(role: :assistant, content: "ok", metadata: { tool_calls: tool_calls, signature: "sig" }),
      TavernKit::Prompt::Message.new(role: :tool, content: "3", metadata: { tool_call_id: "call_1" }),
    ]

    out = TavernKit::Dialects.convert(messages, dialect: :openai)
    assert_equal 2, out.size

    assert_equal "assistant", out[0][:role]
    assert_equal "ok", out[0][:content]
    assert_equal tool_calls, out[0][:tool_calls]
    assert_equal "sig", out[0][:signature]

    assert_equal "tool", out[1][:role]
    assert_equal "3", out[1][:content]
    assert_equal "call_1", out[1][:tool_call_id]
  end

  def test_anthropic_separates_system_and_maps_tool_use_and_tool_result
    messages = [
      TavernKit::Prompt::Message.new(role: :system, content: "SYS"),
      TavernKit::Prompt::Message.new(
        role: :assistant,
        content: "Hello",
        metadata: {
          tool_calls: [
            {
              "id" => "call_1",
              "type" => "function",
              "function" => { "name" => "add", "arguments" => "{\"a\":1}" },
            },
          ],
        },
      ),
      TavernKit::Prompt::Message.new(role: :tool, content: "1", metadata: { tool_call_id: "call_1" }),
    ]

    out = TavernKit::Dialects.convert(messages, dialect: :anthropic)
    assert_equal "SYS", out.fetch(:system)

    out_messages = out.fetch(:messages)
    assert_equal 2, out_messages.size

    assistant = out_messages[0]
    assert_equal "assistant", assistant.fetch(:role)
    assert_equal "text", assistant.fetch(:content)[0].fetch(:type)
    assert_equal "Hello", assistant.fetch(:content)[0].fetch(:text)

    tool_use = assistant.fetch(:content)[1]
    assert_equal "tool_use", tool_use.fetch(:type)
    assert_equal "call_1", tool_use.fetch(:id)
    assert_equal "add", tool_use.fetch(:name)
    assert_equal({ "a" => 1 }, tool_use.fetch(:input))

    tool_result_msg = out_messages[1]
    assert_equal "user", tool_result_msg.fetch(:role)
    tool_result = tool_result_msg.fetch(:content)[0]
    assert_equal "tool_result", tool_result.fetch(:type)
    assert_equal "call_1", tool_result.fetch(:tool_use_id)
    assert_equal "1", tool_result.fetch(:content)
  end

  def test_other_dialects_have_expected_shapes
    msgs = [
      TavernKit::Prompt::Message.new(role: :system, content: "S"),
      TavernKit::Prompt::Message.new(role: :user, content: "U"),
      TavernKit::Prompt::Message.new(role: :assistant, content: "A"),
    ]

    google = TavernKit::Dialects.convert(msgs, dialect: :google)
    assert_kind_of Hash, google
    assert google.key?(:contents)

    cohere = TavernKit::Dialects.convert(msgs, dialect: :cohere)
    assert_kind_of Hash, cohere
    assert_kind_of Array, cohere.fetch(:chat_history)

    ai21 = TavernKit::Dialects.convert(msgs, dialect: :ai21)
    assert_kind_of Array, ai21
    assert_equal "system", ai21[0].fetch(:role)

    mistral = TavernKit::Dialects.convert(msgs, dialect: :mistral)
    assert_kind_of Array, mistral

    xai = TavernKit::Dialects.convert(msgs, dialect: :xai)
    assert_kind_of Array, xai

    text = TavernKit::Dialects.convert(msgs, dialect: :text)
    assert_kind_of Hash, text
    assert_equal "S\nU\nA", text.fetch(:prompt)
  end

  def test_unknown_dialect_raises
    assert_raises(ArgumentError) do
      TavernKit::Dialects.convert([], dialect: :nope)
    end
  end
end
