require "test_helper"

class LLMRunChatTest < ActiveSupport::TestCase
  class FakeTokenEstimator
    def estimate(text, model_hint: nil)
      _ = model_hint
      text.to_s.length
    end
  end

  class FakeClient
    attr_reader :requests

    def initialize(body: nil)
      @requests = []
      @body =
        body || {
          "choices" => [
            {
              "message" => { "role" => "assistant", "content" => "ok" },
              "finish_reason" => "stop",
            },
          ],
        }
    end

    def chat_completions(**params)
      @requests << params
      SimpleInference::Response.new(status: 200, headers: {}, body: @body, raw_body: "{}")
    end
  end

  test "auto-uses key=default preset when none provided" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: { temperature: 0.2 },
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)
    LLMPreset.create!(llm_model: llm_model, key: "default", name: "Default", llm_options_overrides: { temperature: 0.7 })

    client = FakeClient.new
    result = LLM::RunChat.call(llm_model: llm_model, user_text: "hi", client: client)

    assert result.success?
    assert_equal 0.7, client.requests.last.fetch(:temperature)
  end

  test "uses preset_key when provided" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: { temperature: 0.2 },
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)
    LLMPreset.create!(llm_model: llm_model, key: "default", name: "Default", llm_options_overrides: { temperature: 0.7 })
    cold = LLMPreset.create!(llm_model: llm_model, key: "cold", name: "Cold", llm_options_overrides: { temperature: 0.1 })

    client = FakeClient.new
    result = LLM::RunChat.call(llm_model: llm_model, preset_key: "cold", user_text: "hi", client: client)

    assert result.success?
    assert_equal cold.id, result.value.fetch(:preset).id
    assert_equal 0.1, client.requests.last.fetch(:temperature)
  end

  test "fails when preset_key is missing" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)

    client = FakeClient.new
    result = LLM::RunChat.call(llm_model: llm_model, preset_key: "nope", user_text: "hi", client: client)

    assert result.failure?
    assert_equal "PRESET_NOT_FOUND", result.code
    assert_empty client.requests
  end

  test "respects enabled gate but allow_disabled can bypass" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: false)

    client = FakeClient.new
    blocked = LLM::RunChat.call(llm_model: llm_model, user_text: "hi", client: client)
    assert blocked.failure?
    assert_equal "MODEL_DISABLED", blocked.code
    assert_empty client.requests

    allowed = LLM::RunChat.call(llm_model: llm_model, user_text: "hi", client: client, allow_disabled: true)
    assert allowed.success?
    assert_equal 1, client.requests.size
  end

  test "accepts context hash with string keys" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)

    client = FakeClient.new
    result =
      LLM::RunChat.call(
        llm_model: llm_model,
        user_text: "hi",
        client: client,
        context: { "language_policy" => { "enabled" => true, "target_lang" => "zh-CN" } },
      )

    assert result.success?
    runner_config = result.value.fetch(:runner_config)
    assert_kind_of TavernKit::PromptBuilder::Context, runner_config.context
    assert runner_config.context.key?(:language_policy)
  end

  test "normalizes history and appends user_text as last message" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)

    client = FakeClient.new
    result =
      LLM::RunChat.call(
        llm_model: llm_model,
        history: [{ role: "assistant", content: "hello" }],
        user_text: "hi",
        client: client,
      )

    assert result.success?

    request = client.requests.last
    messages = request.fetch(:messages)

    assert_equal 2, messages.size
    assert_equal "user", messages.last.fetch(:role)
    assert_equal "hi", messages.last.fetch(:content)
  end

  test "returns PROMPT_TOO_LONG when prompt exceeds context_window_tokens (and does not call client)" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true, context_window_tokens: 10)

    client = FakeClient.new
    result =
      LLM::RunChat.call(
        llm_model: llm_model,
        history: [{ role: "user", content: "a" * 50 }],
        client: client,
        context: { token_estimation: { token_estimator: FakeTokenEstimator.new, model_hint: "test" } },
      )

    assert result.failure?
    assert_equal "PROMPT_TOO_LONG", result.code
    assert_empty client.requests
    assert_equal 50, result.value.fetch(:estimated_tokens)
    assert_equal 10, result.value.fetch(:max_tokens)
    assert_equal 0, result.value.fetch(:reserve_tokens)
    assert_equal 10, result.value.fetch(:limit_tokens)
  end

  test "message_overhead_tokens inherits from provider when model override is nil" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
        message_overhead_tokens: 5,
      )
    llm_model =
      LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true, context_window_tokens: 4, message_overhead_tokens: nil)

    client = FakeClient.new
    result =
      LLM::RunChat.call(
        llm_model: llm_model,
        user_text: "hi",
        client: client,
        context: { token_estimation: { token_estimator: FakeTokenEstimator.new, model_hint: "test" } },
      )

    assert result.failure?
    assert_equal "PROMPT_TOO_LONG", result.code
    assert_empty client.requests
  end

  test "message_overhead_tokens can be overridden to 0 on model" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
        message_overhead_tokens: 5,
      )
    llm_model =
      LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true, context_window_tokens: 4, message_overhead_tokens: 0)

    client = FakeClient.new
    result =
      LLM::RunChat.call(
        llm_model: llm_model,
        user_text: "hi",
        client: client,
        context: { token_estimation: { token_estimator: FakeTokenEstimator.new, model_hint: "test" } },
      )

    assert result.success?
    assert_equal 1, client.requests.size
  end

  test "reserve_tokens is derived from llm_options.max_tokens (dynamic)" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true, context_window_tokens: 10)

    client = FakeClient.new
    result =
      LLM::RunChat.call(
        llm_model: llm_model,
        user_text: "abc",
        llm_options: { max_tokens: 8 },
        client: client,
        context: { token_estimation: { token_estimator: FakeTokenEstimator.new, model_hint: "test" } },
      )

    assert result.failure?
    assert_equal "PROMPT_TOO_LONG", result.code
    assert_empty client.requests
    assert_equal 3, result.value.fetch(:estimated_tokens)
    assert_equal 10, result.value.fetch(:max_tokens)
    assert_equal 8, result.value.fetch(:reserve_tokens)
    assert_equal 2, result.value.fetch(:limit_tokens)
  end
end
