# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/capabilities"

class CapabilitiesTest < Minitest::Test
  def test_unknown_provider_uses_conservative_defaults
    caps = TavernKit::VibeTavern::Capabilities.resolve(provider: "mystery", model: "mystery-model")

    assert_equal true, caps.supports_tool_calling
    assert_equal true, caps.supports_response_format_json_object
    assert_equal false, caps.supports_response_format_json_schema
    assert_equal true, caps.supports_streaming
    assert_equal false, caps.supports_parallel_tool_calls
  end

  def test_overrides_are_merged
    caps =
      TavernKit::VibeTavern::Capabilities.resolve(
        provider: "openai",
        model: "test-model",
        overrides: { supports_response_format_json_schema: true, supports_parallel_tool_calls: true },
      )

    assert_equal true, caps.supports_response_format_json_schema
    assert_equal true, caps.supports_parallel_tool_calls
  end

  def test_provider_normalization_is_preserved
    caps = TavernKit::VibeTavern::Capabilities.resolve(provider: "Open-Router", model: "test-model")

    assert_equal :open_router, caps.provider
  end
end
