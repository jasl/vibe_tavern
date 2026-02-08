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

  def test_prompt_runner_llm_options_defaults_are_merged_and_reserved_keys_are_stripped
    runner =
      TavernKit::VibeTavern::PromptRunner.new(
        client: Object.new,
        model: "test-model",
        llm_options_defaults: {
          temperature: 0.1,
          tools: [{ type: "function", function: { name: "evil_tool" } }],
          tool_choice: "none",
          response_format: { type: "json_object" },
        },
      )

    prompt_request =
      runner.build_request(
        history: [TavernKit::Prompt::Message.new(role: :user, content: "hi")],
        llm_options: { top_p: 0.9 },
      )

    req = prompt_request.request
    assert_equal 0.1, req.fetch(:temperature)
    assert_equal 0.9, req.fetch(:top_p)

    refute req.key?(:tools)
    refute req.key?(:tool_choice)
    refute req.key?(:response_format)
  end

  def test_prompt_runner_rejects_streaming_in_llm_options_defaults
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::PromptRunner.new(
        client: Object.new,
        model: "test-model",
        llm_options_defaults: { stream: true },
      )
    end
  end

  def test_prompt_runner_rejects_streaming_in_llm_options
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new, model: "test-model")

    assert_raises(ArgumentError) do
      runner.build_request(
        history: [TavernKit::Prompt::Message.new(role: :user, content: "hi")],
        llm_options: { stream: true },
      )
    end
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

  def test_prompt_runner_perform_parses_structured_directives_v1
    requests = []

    structured_output_options = {
      allowed_types: ["ui.show_form"],
      type_aliases: { "show_form" => "ui.show_form" },
    }

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
                  content: JSON.generate(
                    {
                      assistant_text: "ok",
                      directives: [
                        { type: "show_form", payload: { form_id: "character_form_v1" } },
                      ],
                    },
                  ),
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
        structured_output: :directives_v1,
        structured_output_options: structured_output_options,
      )

    result = runner.perform(prompt_request)

    assert result.structured_output.is_a?(Hash)
    assert_equal "ok", result.structured_output.fetch("assistant_text")
    assert_equal "ui.show_form", result.structured_output.fetch("directives")[0].fetch("type")
    assert_empty result.structured_output_warnings
    assert_nil result.structured_output_error
  end

  def test_prompt_runner_perform_returns_structured_output_error_on_invalid_json
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
                  content: "not json",
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
        structured_output: :directives_v1,
      )

    result = runner.perform(prompt_request)

    assert_nil result.structured_output
    assert_equal "INVALID_JSON", result.structured_output_error.fetch(:code)
  end

  def test_prompt_runner_perform_returns_structured_output_error_on_missing_required_fields
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
                  content: JSON.generate({ assistant_text: "ok" }),
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
        structured_output: :directives_v1,
      )

    result = runner.perform(prompt_request)

    assert_nil result.structured_output
    assert_equal "MISSING_DIRECTIVES", result.structured_output_error.fetch(:code)
  end

  def test_prompt_runner_perform_skips_directives_parsing_when_tool_calls_present
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
                  content: JSON.generate({ assistant_text: "ok", directives: [] }),
                  tool_calls: { id: "call_1", type: "function", function: { name: "state_get", arguments: "{}" } },
                },
                finish_reason: "tool_calls",
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
        structured_output: :directives_v1,
      )

    result = runner.perform(prompt_request)

    assert_nil result.structured_output
    assert_nil result.structured_output_error
  end

  def test_prompt_runner_perform_enforces_structured_output_max_bytes
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
                  content: "x" * 50,
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
        structured_output: :directives_v1,
        structured_output_options: { max_bytes: 10 },
      )

    result = runner.perform(prompt_request)

    assert_nil result.structured_output
    assert_equal "TOO_LARGE", result.structured_output_error.fetch(:code)
  end

  def test_prompt_runner_perform_reports_payload_validator_errors_as_warnings
    requests = []

    structured_output_options = {
      allowed_types: ["ui.show_form"],
      payload_validator: lambda do |_type, _payload|
        raise "boom"
      end,
    }

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
                  content: JSON.generate(
                    {
                      assistant_text: "ok",
                      directives: [
                        { type: "ui.show_form", payload: { form_id: "character_form_v1" } },
                      ],
                    },
                  ),
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
        structured_output: :directives_v1,
        structured_output_options: structured_output_options,
      )

    result = runner.perform(prompt_request)

    assert result.structured_output.is_a?(Hash)
    assert_equal "ok", result.structured_output.fetch("assistant_text")
    assert_empty result.structured_output.fetch("directives")

    warnings = result.structured_output_warnings
    assert_equal 1, warnings.size
    assert_equal "PAYLOAD_VALIDATOR_ERROR", warnings[0].fetch(:code)
  end

  def test_prompt_runner_perform_stream_yields_deltas_and_returns_full_content
    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:call) do |_env|
          chunks = []

          chunks << JSON.generate(
            {
              "id" => "evt_1",
              "object" => "chat.completion.chunk",
              "created" => 1,
              "model" => "test-model",
              "choices" => [
                { "index" => 0, "delta" => { "role" => "assistant", "content" => "Hel" }, "finish_reason" => nil },
              ],
            },
          )
          chunks << JSON.generate(
            {
              "id" => "evt_2",
              "object" => "chat.completion.chunk",
              "created" => 1,
              "model" => "test-model",
              "choices" => [
                { "index" => 0, "delta" => { "content" => "lo" }, "finish_reason" => nil },
              ],
            },
          )
          chunks << JSON.generate(
            {
              "id" => "evt_3",
              "object" => "chat.completion.chunk",
              "created" => 1,
              "model" => "test-model",
              "choices" => [
                { "index" => 0, "delta" => {}, "finish_reason" => "stop" },
              ],
              "usage" => { "prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3 },
            },
          )

          sse = chunks.map { |json| "data: #{json}\n\n" }.join
          sse << "data: [DONE]\n\n"

          {
            status: 200,
            headers: { "content-type" => "text/event-stream" },
            body: sse,
          }
        end
      end.new

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::PromptRunner.new(client: client, model: "test-model")

    prompt_request =
      runner.build_request(
        history: [TavernKit::Prompt::Message.new(role: :user, content: "hi")],
      )

    deltas = []
    result = runner.perform_stream(prompt_request) { |delta| deltas << delta }

    assert_equal %w[Hel lo], deltas
    assert_equal "Hello", result.assistant_message.fetch("content")
    assert_equal "stop", result.finish_reason
    assert_equal 1, result.body.dig("usage", "prompt_tokens")
  end

  def test_prompt_runner_perform_stream_rejects_tool_calling_requests
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new, model: "test-model")

    prompt_request =
      runner.build_request(
        history: [TavernKit::Prompt::Message.new(role: :user, content: "hi")],
        llm_options: {
          tools: [{ type: "function", function: { name: "state_get", parameters: { type: "object", properties: {} } } }],
          tool_choice: "auto",
        },
      )

    assert_raises(ArgumentError) { runner.perform_stream(prompt_request) { |_| nil } }
  end

  def test_prompt_runner_perform_stream_rejects_response_format
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new, model: "test-model")

    prompt_request =
      runner.build_request(
        history: [TavernKit::Prompt::Message.new(role: :user, content: "hi")],
        llm_options: { max_tokens: 10, response_format: { type: "json_object" } },
      )

    assert_raises(ArgumentError) { runner.perform_stream(prompt_request) { |_| nil } }
  end
end
