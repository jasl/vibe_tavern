require "test_helper"

class LLMModelTest < ActiveSupport::TestCase
  test "enabled scope filters records" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    enabled = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)
    LLMModel.create!(llm_provider: provider, name: "M2", model: "m2", enabled: false)

    assert_equal [enabled.id], LLMModel.enabled.pluck(:id)
  end

  test "key is globally unique when present" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", key: "quick")

    dupe = LLMModel.new(llm_provider: provider, name: "M2", model: "m2", key: "quick")
    assert_not dupe.valid?
    assert_includes dupe.errors[:key], "has already been taken"
  end

  test "normalizes blank key to nil" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", key: "  ")

    assert_nil llm_model.reload.key
  end

  test "capabilities_overrides reflects capability columns" do
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
        name: "GPT 5.2",
        model: "openai/gpt-5.2:nitro",
        supports_tool_calling: false,
        supports_response_format_json_object: false,
        supports_response_format_json_schema: true,
        supports_streaming: true,
        supports_parallel_tool_calls: true,
      )

    caps = llm_model.capabilities_overrides

    assert_equal false, caps.fetch(:supports_tool_calling)
    assert_equal false, caps.fetch(:supports_response_format_json_object)
    assert_equal true, caps.fetch(:supports_response_format_json_schema)
    assert_equal true, caps.fetch(:supports_streaming)
    assert_equal true, caps.fetch(:supports_parallel_tool_calls)
  end

  test "validates non-negative context_window_tokens" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})

    llm_model = LLMModel.new(llm_provider: provider, name: "M1", model: "m1", context_window_tokens: -1)
    assert_not llm_model.valid?
    assert llm_model.errors[:context_window_tokens].any?
  end

  test "effective_message_overhead_tokens inherits from provider and can be overridden" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
        message_overhead_tokens: 5,
      )

    inherited = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", message_overhead_tokens: nil)
    overridden = LLMModel.create!(llm_provider: provider, name: "M2", model: "m2", message_overhead_tokens: 0)

    assert_equal 5, inherited.effective_message_overhead_tokens
    assert_equal 0, overridden.effective_message_overhead_tokens
  end
end
