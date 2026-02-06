# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/prompt_runner"

class PromptRunnerTest < Minitest::Test
  def test_prompt_runner_build_request_includes_system_message_and_applies_message_transforms
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new, model: "test-model")

    history = [
      TavernKit::Prompt::Message.new(role: :user, content: "hi"),
      TavernKit::Prompt::Message.new(
        role: :assistant,
        content: "",
        metadata: {
          tool_calls: [
            {
              id: "call_1",
              type: "function",
              function: { name: "state_get", arguments: "{}" },
            },
          ],
        },
      ),
    ]

    prompt_request =
      runner.build_request(
        system: "SYS",
        history: history,
        message_transforms: ["assistant_tool_calls_reasoning_content_empty_if_missing"],
      )

    messages = prompt_request.messages
    assert_equal "system", messages[0].fetch(:role)
    assert_equal "SYS", messages[0].fetch(:content)

    assistant_msg = messages.find { |m| m.is_a?(Hash) && m.fetch(:role, nil) == "assistant" && m.fetch(:tool_calls, nil).is_a?(Array) }
    refute_nil assistant_msg
    assert_equal "", assistant_msg.fetch(:reasoning_content)
  end

  def test_prompt_runner_perform_applies_response_transforms
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env

          response_body = {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: "ok",
                  function_call: { name: "state_get", arguments: { workspace_id: "w1" } },
                },
                finish_reason: "stop",
              },
            ],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate(response_body),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::PromptRunner.new(client: client, model: "test-model")

    prompt_request =
      runner.build_request(
        history: [TavernKit::Prompt::Message.new(role: :user, content: "hi")],
        response_transforms: ["assistant_function_call_to_tool_calls"],
      )

    result = runner.perform(prompt_request)

    assistant_msg = result.assistant_message
    tool_calls = assistant_msg.fetch("tool_calls")
    assert tool_calls.is_a?(Array)
    assert_equal "state_get", tool_calls[0].dig("function", "name")

    args = tool_calls[0].dig("function", "arguments").to_s
    assert_includes args, "\"workspace_id\""
  end
end
