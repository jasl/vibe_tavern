require "test_helper"

class LLMProviderTest < ActiveSupport::TestCase
  test "validates basic presence and uniqueness" do
    provider = LLMProvider.new
    assert_not provider.valid?
    assert_includes provider.errors[:name], "can't be blank"
    assert_includes provider.errors[:base_url], "can't be blank"
    assert_includes provider.errors[:api_prefix], "can't be nil"

    LLMProvider.create!(name: "OpenRouter", base_url: "https://openrouter.ai/api", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    dupe = LLMProvider.new(name: "OpenRouter", base_url: "x", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    assert_not dupe.valid?
    assert_includes dupe.errors[:name], "has already been taken"
  end

  test "api_format defaults to openai and rejects unknown formats" do
    provider =
      LLMProvider.new(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )
    assert_equal "openai", provider.api_format
    assert provider.valid?

    provider.api_format = "anthropic"
    assert_not provider.valid?
  end

  test "rejects reserved keys in llm_options_defaults" do
    provider =
      LLMProvider.new(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: { model: "nope" },
      )

    assert_not provider.valid?
    assert provider.errors[:llm_options_defaults].any?
  end

  test "allows blank api_prefix (empty string)" do
    provider =
      LLMProvider.new(
        name: "NoPrefix",
        base_url: "http://example.test",
        api_prefix: "",
        headers: {},
        llm_options_defaults: {},
      )

    assert provider.valid?
  end

  test "validates non-negative message_overhead_tokens" do
    provider =
      LLMProvider.new(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
        message_overhead_tokens: -1,
      )

    assert_not provider.valid?
    assert provider.errors[:message_overhead_tokens].any?
  end

  test "build_simple_inference_client wires base_url and api_prefix" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        api_key: "sk-test",
        headers: { "X-Test" => "1" },
        llm_options_defaults: {},
      )

    client = provider.build_simple_inference_client
    assert_equal "http://example.test", client.config.base_url
    assert_equal "/v1", client.config.api_prefix
    assert_equal "sk-test", client.config.api_key
    assert_equal "1", client.config.headers.fetch("X-Test")
  end

  test "enable_all! and disable_all! toggle models" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    m1 = LLMModel.create!(llm_provider: provider, name: "A", model: "a", enabled: false)
    m2 = LLMModel.create!(llm_provider: provider, name: "B", model: "b", enabled: false)

    provider.enable_all!
    assert_equal true, m1.reload.enabled
    assert_equal true, m2.reload.enabled

    provider.disable_all!
    assert_equal false, m1.reload.enabled
    assert_equal false, m2.reload.enabled
  end
end
