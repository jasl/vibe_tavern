# frozen_string_literal: true

require "json"
require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/prompt_runner"
require_relative "../../lib/tavern_kit/vibe_tavern/runner_config"

class SimpleInferenceContractTest < Minitest::Test
  class SequencedAdapter < SimpleInference::HTTPAdapter
    def initialize
      @call_index = 0
    end

    def call(_env)
      @call_index += 1

      case @call_index
      when 1
        json(
          {
            choices: [
              { message: { role: "assistant", content: "hello" }, finish_reason: "stop" },
            ],
            usage: { prompt_tokens: 1, completion_tokens: 2, total_tokens: 3 },
          },
        )
      when 2
        json(
          {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: "",
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: { name: "state_get", arguments: "{\"workspace_id\":\"w1\"}" },
                    },
                  ],
                },
                finish_reason: "stop",
              },
            ],
          },
        )
      when 3
        json({ error: { message: "nope" } }, status: 401)
      when 4
        sse = +""

        sse << "data: #{JSON.generate(sse_chunk(content: "Hel", finish_reason: nil))}\n\n"
        sse << "data: #{JSON.generate(sse_chunk(content: "lo", finish_reason: nil))}\n\n"
        sse << "data: #{JSON.generate(sse_chunk(content: nil, finish_reason: "stop", include_usage: true))}\n\n"
        sse << "data: [DONE]\n\n"

        { status: 200, headers: { "content-type" => "text/event-stream" }, body: sse }
      else
        raise "Unexpected request (call_index=#{@call_index})"
      end
    end

    private

    def json(body, status: 200)
      {
        status: status,
        headers: { "content-type" => "application/json" },
        body: JSON.generate(body),
      }
    end

    def sse_chunk(content:, finish_reason:, include_usage: false)
      chunk =
        {
          "id" => "evt_#{@call_index}",
          "object" => "chat.completion.chunk",
          "created" => 1,
          "model" => "test-model",
          "choices" => [
            {
              "index" => 0,
              "delta" => {},
              "finish_reason" => finish_reason,
            },
          ],
        }

      if content
        chunk["choices"][0]["delta"]["role"] = "assistant"
        chunk["choices"][0]["delta"]["content"] = content
      end

      if include_usage
        chunk["usage"] = { "prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3 }
      end

      chunk
    end
  end

  def assert_vibe_tavern_client_contract(client:)
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openai",
        model: "test-model",
      )

    runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
    history = [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")]

    prompt_request = runner.build_request(runner_config: runner_config, history: history)
    result = runner.perform(prompt_request)
    assert_instance_of SimpleInference::Response, result.response
    assert result.response.raw_body.is_a?(String)
    assert_equal "hello", result.assistant_message.fetch("content")
    assert_equal "stop", result.finish_reason

    tool_request = runner.build_request(runner_config: runner_config, history: history)
    tool_result = runner.perform(tool_request)
    assert_instance_of SimpleInference::Response, tool_result.response
    tool_calls = tool_result.assistant_message.fetch("tool_calls")
    assert tool_calls.is_a?(Array)
    assert_equal "call_1", tool_calls.dig(0, "id")
    assert_equal "function", tool_calls.dig(0, "type")
    assert_equal "state_get", tool_calls.dig(0, "function", "name")
    assert_includes tool_calls.dig(0, "function", "arguments").to_s, "\"workspace_id\""

    error_request = runner.build_request(runner_config: runner_config, history: history)
    error =
      assert_raises(SimpleInference::Errors::HTTPError) do
        runner.perform(error_request)
      end
    assert_equal 401, error.status
    assert error.body.is_a?(Hash)
    assert_includes error.message, "nope"
    assert_includes error.raw_body.to_s, "nope"

    stream_request = runner.build_request(runner_config: runner_config, history: history)
    deltas = []
    stream_result = runner.perform_stream(stream_request) { |delta| deltas << delta }
    assert_instance_of SimpleInference::Response, stream_result.response
    assert_equal 200, stream_result.response.status
    assert_equal %w[Hel lo], deltas
    assert_equal "Hello", stream_result.assistant_message.fetch("content")
    assert_equal "stop", stream_result.finish_reason
    assert_equal 1, stream_result.body.dig("usage", "prompt_tokens")
  end

  def test_simple_inference_client_satisfies_vibe_tavern_client_contract
    adapter = SequencedAdapter.new
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    assert_vibe_tavern_client_contract(client: client)
  end
end
