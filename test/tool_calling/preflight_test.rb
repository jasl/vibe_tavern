# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/preflight"

class PreflightTest < Minitest::Test
  def build_capabilities(**overrides)
    TavernKit::VibeTavern::Capabilities.resolve(provider: "openrouter", model: "test-model").with(**overrides)
  end

  def test_validate_request_rejects_unsupported_tools
    capabilities = build_capabilities(supports_tool_calling: false)

    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::Preflight.validate_request!(
          capabilities: capabilities,
          stream: false,
          tools: true,
          response_format: nil,
        )
      end

    assert_includes error.message, "does not support tools"
  end

  def test_validate_request_rejects_unsupported_json_schema
    capabilities = build_capabilities(supports_response_format_json_schema: false)

    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::Preflight.validate_request!(
          capabilities: capabilities,
          stream: false,
          tools: false,
          response_format: { type: "json_schema" },
        )
      end

    assert_includes error.message, "json_schema"
  end

  def test_validate_request_rejects_unsupported_streaming
    capabilities = build_capabilities(supports_streaming: false)

    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::Preflight.validate_request!(
          capabilities: capabilities,
          stream: true,
          tools: false,
          response_format: nil,
        )
      end

    assert_includes error.message, "does not support streaming"
  end

  def test_validate_request_rejects_tools_with_response_format
    capabilities = build_capabilities

    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::Preflight.validate_request!(
          capabilities: capabilities,
          stream: false,
          tools: true,
          response_format: { type: "json_object" },
        )
      end

    assert_includes error.message, "cannot be used in the same request"
  end
end
