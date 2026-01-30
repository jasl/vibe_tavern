# frozen_string_literal: true

require "test_helper"

class Wave4DialectsContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/dialects", __dir__)

  def pending!(reason)
    skip("Pending Wave 4 (Dialects): #{reason}")
  end

  def test_openai_tool_calls_passthrough
    pending!("Core Dialects.convert must map Message.metadata tool_calls/tool_call_id into OpenAI chat format")

    expected = JSON.parse(File.read(File.join(FIXTURES_DIR, "openai_tool_calls.json")))

    messages = [
      TavernKit::Prompt::Message.new(role: :user, content: "What's the weather in Boston?"),
      TavernKit::Prompt::Message.new(
        role: :assistant,
        content: "",
        metadata: {
          tool_calls: [
            {
              id: "call_123",
              type: "function",
              function: {
                name: "get_weather",
                arguments: "{\"location\":\"Boston, MA\"}",
              },
            },
          ],
        },
      ),
      TavernKit::Prompt::Message.new(
        role: :tool,
        content: "{\"temp_f\":32}",
        metadata: { tool_call_id: "call_123" },
      ),
    ]

    output = TavernKit::Dialects.convert(messages, dialect: :openai)
    assert_equal expected, output
  end

  def test_anthropic_tool_use_mapping
    pending!("Core Dialects.convert must map tool_calls into Anthropic tool_use/tool_result content blocks")

    expected = JSON.parse(File.read(File.join(FIXTURES_DIR, "anthropic_tool_use.json")))

    messages = [
      TavernKit::Prompt::Message.new(role: :system, content: "You are a helpful assistant."),
      TavernKit::Prompt::Message.new(role: :user, content: "What's the weather in Boston?"),
      TavernKit::Prompt::Message.new(
        role: :assistant,
        content: "",
        metadata: {
          tool_calls: [
            {
              id: "toolu_123",
              type: "function",
              function: {
                name: "get_weather",
                arguments: "{\"location\":\"Boston, MA\"}",
              },
            },
          ],
        },
      ),
      TavernKit::Prompt::Message.new(
        role: :tool,
        content: "{\"temp_f\":32}",
        metadata: { tool_call_id: "toolu_123" },
      ),
    ]

    output = TavernKit::Dialects.convert(messages, dialect: :anthropic)
    assert_equal expected, output
  end
end
