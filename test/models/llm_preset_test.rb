require "test_helper"

class LLMPresetTest < ActiveSupport::TestCase
  test "key is optional but unique per model when present" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1")

    LLMPreset.create!(llm_model: llm_model, key: "default", name: "Default", llm_options_overrides: {})

    dupe = LLMPreset.new(llm_model: llm_model, key: "default", name: "Other", llm_options_overrides: {})
    assert_not dupe.valid?
    assert_includes dupe.errors[:key], "has already been taken"

    nil_key = LLMPreset.new(llm_model: llm_model, key: nil, name: "No key", llm_options_overrides: {})
    assert nil_key.valid?
  end

  test "normalizes blank key to nil" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1")

    preset = LLMPreset.create!(llm_model: llm_model, key: "  ", name: "Blank", llm_options_overrides: {})
    assert_nil preset.reload.key
  end

  test "rejects reserved keys in llm_options_overrides" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1")

    preset =
      LLMPreset.new(
        llm_model: llm_model,
        name: "Bad",
        llm_options_overrides: { messages: [] },
      )

    assert_not preset.valid?
    assert preset.errors[:llm_options_overrides].any?
  end
end
