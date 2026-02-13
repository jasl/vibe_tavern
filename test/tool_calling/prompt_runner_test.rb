# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/prompt_runner"

class PromptRunnerTest < Minitest::Test
  def build_runner_config(
    context: nil,
    llm_options_defaults: nil,
    provider: "openrouter",
    model: "test-model",
    capabilities_overrides: nil
  )
    config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: provider,
        model: model,
        context: context,
        llm_options_defaults: llm_options_defaults,
      )

    return config unless capabilities_overrides.is_a?(Hash)

    capabilities = config.capabilities.with(**capabilities_overrides)
    config.with(capabilities: capabilities)
  end

  def test_prompt_runner_rejects_tools_when_capability_is_disabled
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config =
      build_runner_config(
        capabilities_overrides: { supports_tool_calling: false },
      )

    error =
      assert_raises(ArgumentError) do
        runner.build_request(
          runner_config: runner_config,
          history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
          llm_options: {
            tools: [{ type: "function", function: { name: "state_get", parameters: { type: "object", properties: {} } } }],
          },
        )
      end

    assert_includes error.message, "does not support tools"
  end

  def test_prompt_runner_perform_stream_rejects_when_streaming_capability_is_disabled
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config =
      build_runner_config(
        capabilities_overrides: { supports_streaming: false },
      )

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    error = assert_raises(ArgumentError) { runner.perform_stream(prompt_request) { |_| nil } }
    assert_includes error.message, "does not support streaming"
  end

  def test_prompt_runner_build_request_includes_system_message_and_applies_message_transforms
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config

    history = [
      TavernKit::PromptBuilder::Message.new(role: :user, content: "hi"),
      TavernKit::PromptBuilder::Message.new(
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
        runner_config: runner_config,
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

  def test_prompt_runner_llm_options_defaults_are_merged
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config(llm_options_defaults: { temperature: 0.1 })

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { top_p: 0.9 },
      )

    req = prompt_request.request
    assert_equal 0.1, req.fetch(:temperature)
    assert_equal 0.9, req.fetch(:top_p)
  end

  def test_runner_config_rejects_reserved_llm_options_defaults_keys
    assert_raises(ArgumentError) do
      build_runner_config(
        llm_options_defaults: {
          temperature: 0.1,
          tools: [{ type: "function", function: { name: "evil_tool" } }],
        },
      )
    end
  end

  def test_prompt_runner_rejects_streaming_in_llm_options_defaults
    assert_raises(ArgumentError) do
      build_runner_config(llm_options_defaults: { stream: true })
    end
  end

  def test_prompt_runner_rejects_streaming_in_llm_options
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config

    assert_raises(ArgumentError) do
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { stream: true },
      )
    end
  end

  def test_prompt_runner_rejects_tools_and_response_format_in_the_same_request
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config

    assert_raises(ArgumentError) do
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: {
          tools: [{ type: "function", function: { name: "state_get", parameters: { type: "object", properties: {} } } }],
          response_format: { type: "json_object" },
        },
      )
    end
  end

  def test_prompt_runner_rejects_dialects_that_do_not_return_openai_messages
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config

    error =
      assert_raises(ArgumentError) do
        runner.build_request(
          runner_config: runner_config,
          history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
          dialect: :anthropic,
        )
      end

    assert_includes error.message, "messages Array"
    assert_includes error.message, "dialect"
  end

  def test_prompt_runner_does_not_send_parallel_tool_calls_when_capability_is_disabled
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config =
      build_runner_config(
        capabilities_overrides: { supports_parallel_tool_calls: false },
      )

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { response_format: { type: "json_object" } },
      )

    refute prompt_request.request.key?(:parallel_tool_calls)
  end

  def test_prompt_runner_defaults_parallel_tool_calls_false_for_tool_calling
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: {
          tools: [{ type: "function", function: { name: "state_get", parameters: { type: "object", properties: {} } } }],
        },
      )

    assert_equal false, prompt_request.options.fetch(:parallel_tool_calls)
  end

  def test_prompt_runner_filters_parallel_tool_calls_from_request_when_unsupported
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    supported =
      build_runner_config(
        capabilities_overrides: { supports_parallel_tool_calls: true },
      )
    unsupported =
      build_runner_config(
        capabilities_overrides: { supports_parallel_tool_calls: false },
      )

    prompt_request_supported =
      runner.build_request(
        runner_config: supported,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: {
          tools: [{ type: "function", function: { name: "state_get", parameters: { type: "object", properties: {} } } }],
          parallel_tool_calls: true,
        },
      )

    assert_equal true, prompt_request_supported.request.fetch(:parallel_tool_calls)

    prompt_request_unsupported =
      runner.build_request(
        runner_config: unsupported,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: {
          tools: [{ type: "function", function: { name: "state_get", parameters: { type: "object", properties: {} } } }],
          parallel_tool_calls: true,
        },
      )

    assert_equal true, prompt_request_unsupported.options.fetch(:parallel_tool_calls)
    refute prompt_request_unsupported.request.key?(:parallel_tool_calls)
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
    runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
    runner_config = build_runner_config

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
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

  def test_prompt_runner_perform_is_transport_only_and_keeps_raw_content
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
                  content: %(Hello <lang code="ja">ありがとう</lang>.),
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

    context =
      {
        output_tags: {
          enabled: true,
          rules: [{ tag: "lang", action: :strip }],
          sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
        },
      }

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
    runner_config = build_runner_config(context: context)

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    result = runner.perform(prompt_request)
    assert_equal %(Hello <lang code="ja">ありがとう</lang>.), result.assistant_message.fetch("content")
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
    runner = TavernKit::VibeTavern::PromptRunner.new(client: client)
    runner_config = build_runner_config

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    deltas = []
    result = runner.perform_stream(prompt_request) { |delta| deltas << delta }

    assert_equal %w[Hel lo], deltas
    assert_equal "Hello", result.assistant_message.fetch("content")
    assert_equal "stop", result.finish_reason
    assert_equal 1, result.body.dig("usage", "prompt_tokens")
  end

  def test_prompt_runner_perform_stream_rejects_tool_calling_requests
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: {
          tools: [{ type: "function", function: { name: "state_get", parameters: { type: "object", properties: {} } } }],
          tool_choice: "auto",
        },
      )

    assert_raises(ArgumentError) { runner.perform_stream(prompt_request) { |_| nil } }
  end

  def test_prompt_runner_perform_stream_rejects_response_format
    runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
    runner_config = build_runner_config

    prompt_request =
      runner.build_request(
        runner_config: runner_config,
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { max_tokens: 10, response_format: { type: "json_object" } },
      )

    assert_raises(ArgumentError) { runner.perform_stream(prompt_request) { |_| nil } }
  end
end
