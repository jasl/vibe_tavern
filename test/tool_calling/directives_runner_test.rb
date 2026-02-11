# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/directives/runner"

class DirectivesRunnerTest < Minitest::Test
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

  def test_directives_runner_skips_unsupported_structured_mode_by_capability
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    context = { directives: { modes: %i[json_schema json_object] } }
    runner_config =
      build_runner_config(
        context: context,
        capabilities_overrides: {
          supports_response_format_json_schema: false,
          supports_response_format_json_object: true,
        },
      )
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal true, result[:ok]
    assert_equal :json_object, result[:mode]
    assert_equal 2, result[:attempts].size
    assert_equal true, result[:attempts][0].fetch(:skipped)
    assert_equal "CAPABILITY_UNSUPPORTED", result[:attempts][0].dig(:structured_output_error, :code)
    assert_equal :json_schema, result[:attempts][0].fetch(:mode)
    assert_equal :json_object, result[:attempts][1].fetch(:mode)

    request_bodies = requests.map { |env| JSON.parse(env[:body]) }
    assert_equal ["json_object"], request_bodies.map { |body| body.dig("response_format", "type") }
  end

  def test_directives_runner_returns_failure_when_all_configured_modes_are_unsupported
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          {
            status: 500,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ error: { message: "unexpected request" } }),
          }
        end
      end.new(requests)

    context = { directives: { modes: [:json_schema] } }
    runner_config =
      build_runner_config(
        context: context,
        capabilities_overrides: {
          supports_response_format_json_schema: false,
        },
      )
    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal false, result[:ok]
    assert_equal "", result[:assistant_text]
    assert_equal 1, result[:attempts].size
    assert_equal true, result[:attempts][0].fetch(:skipped)
    assert_equal "CAPABILITY_UNSUPPORTED", result[:attempts][0].dig(:structured_output_error, :code)
    assert_equal [], requests
  end

  def build_runner(client:, runner_config:)
    TavernKit::VibeTavern::Directives::Runner.build(
      client: client,
      runner_config: runner_config,
    )
  end

  def test_directives_runner_disables_openrouter_require_parameters_in_prompt_only_via_presets
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          body = JSON.parse(env[:body])

          provider = body["provider"]
          require_parameters = provider.is_a?(Hash) ? provider["require_parameters"] : nil

          if require_parameters == true
            return {
              status: 404,
              headers: { "content-type" => "application/json" },
              body: JSON.generate({ error: { message: "No endpoints found that can handle the requested parameters." } }),
            }
          end

          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    context = { directives: TavernKit::VibeTavern::Directives::Presets.provider_defaults("openrouter", require_parameters: true) }
    runner_config = build_runner_config(provider: "openrouter", context: context)
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal true, result[:ok]
    assert_equal :prompt_only, result[:mode]
    assert_equal "ui.toast", result[:directives][0].fetch("type")

    assert_equal 3, result[:attempts].size
    assert_equal true, result[:attempts][0].fetch(:http_error)
    assert_equal true, result[:attempts][1].fetch(:http_error)
    assert_equal true, result[:attempts][2].fetch(:ok)

    request_bodies = requests.map { |env| JSON.parse(env[:body]) }
    assert_equal true, request_bodies[0].dig("provider", "require_parameters")
    assert_equal true, request_bodies[1].dig("provider", "require_parameters")
    assert_equal false, request_bodies[2].dig("provider", "require_parameters")
  end

  def test_directives_runner_rejects_reserved_llm_options_keys_to_avoid_tool_leakage
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env

          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context =
      {
        directives:
          TavernKit::VibeTavern::Directives::Presets.directives(
            modes: [:json_schema],
            request_overrides: {
              temperature: 0.1,
              tools: [{ type: "function", function: { name: "evil_tool" } }],
              tool_choice: "none",
            },
          ),
      }
    runner_config = build_runner_config(context: context)
    runner = build_runner(client: client, runner_config: runner_config)

    assert_raises(ArgumentError) do
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )
    end
  end

  def test_directives_runner_propagates_llm_options_defaults
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env

          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)

    context = { directives: TavernKit::VibeTavern::Directives::Presets.directives(modes: [:prompt_only]) }
    runner_config = build_runner_config(context: context, llm_options_defaults: { temperature: 0.7 })
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal true, result[:ok]

    req = JSON.parse(requests[0][:body])
    assert_in_delta 0.7, req.fetch("temperature"), 0.0001
  end

  def test_directives_runner_injects_language_policy_via_context
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env

          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    context = { language_policy: { enabled: true, target_lang: "ja-JP" } }
    runner_config = build_runner_config(context: context)
    runner = build_runner(client: client, runner_config: runner_config)
    result =
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal true, result[:ok]

    req = JSON.parse(requests[0][:body])
    system_texts =
      Array(req["messages"]).filter_map do |m|
        next unless m.is_a?(Hash) && m["role"] == "system"

        m["content"].to_s
      end

    assert system_texts.any? { |t| t.include?("Language Policy:") && t.include?("Respond in: ja-JP") }
    assert req["response_format"].is_a?(Hash)
  end

  def test_directives_runner_falls_back_from_json_schema_to_json_object
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          body = JSON.parse(env[:body])
          response_format = body["response_format"]
          if response_format.is_a?(Hash) && response_format["type"].to_s == "json_schema"
            return {
              status: 400,
              headers: { "content-type" => "application/json" },
              body: JSON.generate({ error: { message: "response_format json_schema not supported" } }),
            }
          end

          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner_config = build_runner_config
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { temperature: 0 },
      )

    assert_equal true, result[:ok]
    assert_equal :json_object, result[:mode]
    assert_equal "ok", result[:assistant_text]
    assert_equal "ui.toast", result[:directives][0].fetch("type")

    assert_equal 2, result[:attempts].size
    assert_equal :json_schema, result[:attempts][0].fetch(:mode)
    assert_equal true, result[:attempts][0].fetch(:http_error)
    assert_equal :json_object, result[:attempts][1].fetch(:mode)
    assert_equal true, result[:attempts][1].fetch(:ok)
  end

  def test_directives_runner_repair_retries_on_invalid_json
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          content =
            if @call_count == 1
              "not json"
            else
              JSON.generate(
                {
                  assistant_text: "ok",
                  directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
                },
              )
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: content }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner_config = build_runner_config
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { temperature: 0 },
      )

    assert_equal true, result[:ok]
    assert_equal :json_schema, result[:mode]
    assert_equal "ok", result[:assistant_text]
    assert_equal 2, result[:attempts].size
  end

  def test_directives_runner_repair_retries_on_result_validation_failure
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
          @call_count = 0
        end

        define_method(:call) do |env|
          @requests << env
          @call_count += 1

          envelope =
            if @call_count == 1
              { assistant_text: "ok", directives: [] }
            else
              { assistant_text: "ok", directives: [{ type: "ui.toast", payload: { message: "Saved." } }] }
            end

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner_config = build_runner_config
    runner = build_runner(client: client, runner_config: runner_config)

    result_validator =
      lambda do |result|
        dirs = Array(result[:directives])
        dirs.any? { |d| d.is_a?(Hash) && d["type"] == "ui.toast" } ? [] : ["missing ui.toast"]
      end

    result =
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { temperature: 0 },
        result_validator: result_validator,
      )

    assert_equal true, result[:ok]
    assert_equal :json_schema, result[:mode]
    assert_equal "ok", result[:assistant_text]

    assert_equal 2, result[:attempts].size
    assert_equal "ASSERTION_FAILED", result[:attempts][0].dig(:semantic_error, :code)
    assert_equal ["missing ui.toast"], result[:attempts][0].dig(:semantic_error, :reasons)
    assert_nil result[:attempts][1].fetch(:semantic_error)
  end

  def test_directives_runner_falls_back_to_prompt_only_when_response_format_is_unsupported
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          body = JSON.parse(env[:body])
          response_format = body["response_format"]

          if response_format.is_a?(Hash)
            return {
              status: 400,
              headers: { "content-type" => "application/json" },
              body: JSON.generate({ error: { message: "response_format is unsupported" } }),
            }
          end

          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.show_form", payload: { form_id: "character_form_v1" } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner_config = build_runner_config
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        system: "SYS",
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        llm_options: { temperature: 0 },
      )

    assert_equal true, result[:ok]
    assert_equal :prompt_only, result[:mode]
    assert_equal "ui.show_form", result[:directives][0].fetch("type")
  end

  def test_directives_runner_forces_parallel_tool_calls_false_for_structured_modes
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env
          envelope = {
            assistant_text: "ok",
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
          }
        end
      end.new(requests)

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "secret", adapter: adapter)
    runner_config = build_runner_config(context: { directives: { modes: [:json_schema] } })
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal true, result[:ok]
    request_body = JSON.parse(requests[0][:body])
    assert_equal false, request_body.fetch("parallel_tool_calls")
  end

  def test_directives_runner_returns_structured_error_when_tool_calls_are_present
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
                  content: "",
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: { name: "state_get", arguments: "{}" },
                    },
                  ],
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
    runner_config =
      build_runner_config(
        context: {
          directives: {
            modes: [:json_schema],
            repair_retry_count: 0,
          },
        },
      )
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal false, result[:ok]
    assert_equal 1, result[:attempts].size
    assert_equal "TOOL_CALLS_PRESENT", result[:attempts][0].dig(:structured_output_error, :code)
  end

  def test_directives_runner_applies_output_tags_to_assistant_text
    requests = []

    adapter =
      Class.new(SimpleInference::HTTPAdapter) do
        define_method(:initialize) do |requests|
          @requests = requests
        end

        define_method(:call) do |env|
          @requests << env

          envelope = {
            assistant_text: %(Hi <lang code="ja">ありがとう</lang>.),
            directives: [{ type: "ui.toast", payload: { message: "Saved." } }],
          }

          {
            status: 200,
            headers: { "content-type" => "application/json" },
            body: JSON.generate({ choices: [{ message: { role: "assistant", content: JSON.generate(envelope) }, finish_reason: "stop" }] }),
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
    runner_config = build_runner_config(context: context)
    runner = build_runner(client: client, runner_config: runner_config)

    result =
      runner.run(
        history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
      )

    assert_equal true, result[:ok]
    assert_equal "Hi ありがとう.", result[:assistant_text]
    assert_equal "Hi ありがとう.", result[:envelope].fetch("assistant_text")
  end
end
