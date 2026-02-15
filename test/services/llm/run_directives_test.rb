# frozen_string_literal: true

require "test_helper"

class LLMRunDirectivesTest < ActiveSupport::TestCase
  class FakeTokenEstimator
    def estimate(text, model_hint: nil)
      _ = model_hint
      text.to_s.length
    end
  end

  class FakeClient
    attr_reader :requests

    def initialize(body:)
      @requests = []
      @body = body
    end

    def chat_completions(**params)
      @requests << params
      SimpleInference::Response.new(status: 200, headers: {}, body: @body, raw_body: "{}")
    end
  end

  test "runs directives with preset overrides and json_schema response_format when supported" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: { temperature: 0.2 },
      )

    llm_model =
      LLMModel.create!(
        llm_provider: provider,
        name: "M1",
        model: "m1",
        enabled: true,
        supports_response_format_json_schema: true,
      )
    LLMPreset.create!(llm_model: llm_model, key: "default", name: "Default", llm_options_overrides: { temperature: 0.7 })

    body = {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => "{\"assistant_text\":\"ok\",\"directives\":[]}",
          },
          "finish_reason" => "stop",
        },
      ],
    }

    client = FakeClient.new(body: body)
    result =
      LLM::RunDirectives.call(
        llm_model: llm_model,
        history: [{ role: "user", content: "hi" }],
        client: client,
      )

    assert result.success?
    assert_equal 0.7, client.requests.last.fetch(:temperature)

    response_format = client.requests.last.fetch(:response_format)
    assert_equal "json_schema", response_format.fetch(:type)

    directives_result = result.value.fetch(:directives_result)
    assert_equal true, directives_result.fetch(:ok)
    assert_equal "ok", directives_result.fetch(:assistant_text)
  end

  test "returns PROMPT_TOO_LONG when preflight exceeds context window (and does not call client)" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model =
      LLMModel.create!(
        llm_provider: provider,
        name: "M1",
        model: "m1",
        enabled: true,
        context_window_tokens: 10,
      )

    body = {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => "{\"assistant_text\":\"ok\",\"directives\":[]}",
          },
          "finish_reason" => "stop",
        },
      ],
    }
    client = FakeClient.new(body: body)

    result =
      LLM::RunDirectives.call(
        llm_model: llm_model,
        history: [{ role: "user", content: "a" * 50 }],
        client: client,
        context: { token_estimation: { token_estimator: FakeTokenEstimator.new, model_hint: "test" } },
      )

    assert result.failure?
    assert_equal "PROMPT_TOO_LONG", result.code
    assert_empty client.requests
    assert result.value.fetch(:estimated_tokens).is_a?(Integer)
    assert_equal 10, result.value.fetch(:max_tokens)
  end

  test "rejects reserved llm_options keys" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)

    body = {
      "choices" => [
        {
          "message" => { "role" => "assistant", "content" => "{\"assistant_text\":\"ok\",\"directives\":[]}" },
          "finish_reason" => "stop",
        },
      ],
    }
    client = FakeClient.new(body: body)

    result = LLM::RunDirectives.call(llm_model: llm_model, history: [{ role: "user", content: "hi" }], client: client, llm_options: { model: "nope" })

    assert result.failure?
    assert_equal "INVALID_INPUT", result.code
    assert_empty client.requests
  end
end
