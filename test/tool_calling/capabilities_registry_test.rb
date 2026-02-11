# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/capabilities"

class CapabilitiesRegistryTest < Minitest::Test
  def test_openrouter_openai_routes_disable_structured_response_format
    caps =
      TavernKit::VibeTavern::Capabilities.resolve(
        provider: "openrouter",
        model: "openai/gpt-5.2:nitro",
      )

    assert_equal false, caps.supports_response_format_json_schema
    assert_equal false, caps.supports_response_format_json_object
    assert_equal true, caps.supports_tools
    assert_equal true, caps.supports_streaming
  end

  def test_openrouter_anthropic_routes_disable_json_schema_but_keep_json_object
    caps =
      TavernKit::VibeTavern::Capabilities.resolve(
        provider: "openrouter",
        model: "anthropic/claude-opus-4.6:nitro",
      )

    assert_equal false, caps.supports_response_format_json_schema
    assert_equal true, caps.supports_response_format_json_object
  end

  def test_openrouter_google_routes_keep_json_schema
    caps =
      TavernKit::VibeTavern::Capabilities.resolve(
        provider: "openrouter",
        model: "google/gemini-2.5-flash:nitro",
      )

    assert_equal true, caps.supports_response_format_json_schema
    assert_equal true, caps.supports_response_format_json_object
  end

  def test_unknown_provider_uses_conservative_defaults
    caps =
      TavernKit::VibeTavern::Capabilities.resolve(
        provider: "mystery",
        model: "mystery-model",
      )

    assert_equal true, caps.supports_tools
    assert_equal true, caps.supports_response_format_json_object
    assert_equal false, caps.supports_response_format_json_schema
    assert_equal true, caps.supports_streaming
    assert_equal false, caps.supports_parallel_tool_calls
  end

  def test_provider_normalization_is_preserved
    caps =
      TavernKit::VibeTavern::Capabilities.resolve(
        provider: "Open-Router",
        model: "google/gemini-2.5-flash:nitro",
      )

    assert_equal :open_router, caps.provider
    assert_equal true, caps.supports_response_format_json_schema
    assert_equal true, caps.supports_parallel_tool_calls
  end
end
