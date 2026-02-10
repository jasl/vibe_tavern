# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/presets"

class PresetsTest < Minitest::Test
  def test_merge_deep_merges_request_overrides_and_unions_tool_lists
    a =
      TavernKit::VibeTavern::ToolCalling::Presets.tool_calling(
        tool_allowlist: ["state_get"],
        request_overrides: { temperature: 0.1, provider: { only: ["p1"] } },
      )

    b =
      TavernKit::VibeTavern::ToolCalling::Presets.tool_calling(
        tool_allowlist: "state_patch",
        request_overrides: { provider: { order: ["p2"] }, top_p: 0.9 },
      )

    merged = TavernKit::VibeTavern::ToolCalling::Presets.merge(a, b)

    assert_equal ["state_get", "state_patch"], merged[:tool_allowlist]
    assert_equal 0.1, merged.dig(:request_overrides, :temperature)
    assert_equal 0.9, merged.dig(:request_overrides, :top_p)
    assert_equal ["p1"], merged.dig(:request_overrides, :provider, :only)
    assert_equal ["p2"], merged.dig(:request_overrides, :provider, :order)
  end

  def test_merge_can_clear_tool_allowlist_with_an_explicit_empty_list
    merged =
      TavernKit::VibeTavern::ToolCalling::Presets.merge(
        { tool_allowlist: ["a"] },
        { tool_allowlist: [] },
      )

    assert_equal [], merged[:tool_allowlist]
  end

  def test_merge_unions_message_transforms
    merged =
      TavernKit::VibeTavern::ToolCalling::Presets.merge(
        { message_transforms: ["a"] },
        { message_transforms: ["b"] },
      )

    assert_equal ["a", "b"], merged[:message_transforms]
  end

  def test_merge_unions_tool_and_response_transforms
    merged =
      TavernKit::VibeTavern::ToolCalling::Presets.merge(
        {
          tool_transforms: ["a"],
          response_transforms: ["c"],
          tool_call_transforms: ["e"],
          tool_result_transforms: ["g"],
        },
        {
          tool_transforms: ["b"],
          response_transforms: ["d"],
          tool_call_transforms: ["f"],
          tool_result_transforms: ["h"],
        },
      )

    assert_equal ["a", "b"], merged[:tool_transforms]
    assert_equal ["c", "d"], merged[:response_transforms]
    assert_equal ["e", "f"], merged[:tool_call_transforms]
    assert_equal ["g", "h"], merged[:tool_result_transforms]
  end

  def test_model_defaults_can_disable_tools_for_known_unsupported_models
    cfg = TavernKit::VibeTavern::ToolCalling::Presets.model_defaults("minimax/minimax-m2-her")
    assert_equal :disabled, cfg[:tool_use_mode]
  end

  def test_model_defaults_adds_deepseek_compat_message_transform
    cfg = TavernKit::VibeTavern::ToolCalling::Presets.model_defaults("deepseek/deepseek-chat-v3-0324:nitro")
    transforms = Array(cfg[:message_transforms]).map(&:to_s)
    assert_includes transforms, "assistant_tool_calls_reasoning_content_empty_if_missing"
  end

  def test_model_defaults_adds_gemini_compat_message_transform
    cfg = TavernKit::VibeTavern::ToolCalling::Presets.model_defaults("google/gemini-3-pro-preview:nitro")
    transforms = Array(cfg[:message_transforms]).map(&:to_s)
    assert_includes transforms, "assistant_tool_calls_signature_skip_validator_if_missing"
  end

  def test_default_tool_calling_normalizes_blank_tool_call_arguments
    cfg = TavernKit::VibeTavern::ToolCalling::Presets.default_tool_calling
    tool_call_transforms = Array(cfg[:tool_call_transforms]).map(&:to_s)
    assert_includes tool_call_transforms, "assistant_tool_calls_arguments_blank_to_empty_object"

    response_transforms = Array(cfg[:response_transforms]).map(&:to_s)
    assert_includes response_transforms, "assistant_function_call_to_tool_calls"
    assert_includes response_transforms, "assistant_tool_calls_object_to_array"
    assert_includes response_transforms, "assistant_tool_calls_arguments_json_string_if_hash"
  end

  def test_provider_defaults_for_openrouter_include_sequential_tool_calling_reliability_defaults
    cfg = TavernKit::VibeTavern::ToolCalling::Presets.provider_defaults("openrouter")
    assert_equal false, cfg.dig(:request_overrides, :parallel_tool_calls)

    response_transforms = Array(cfg[:response_transforms]).map(&:to_s)
    assert_includes response_transforms, "assistant_function_call_to_tool_calls"
    assert_includes response_transforms, "assistant_tool_calls_object_to_array"
  end

  def test_provider_defaults_for_openai_include_sequential_tool_calling_reliability_defaults
    cfg = TavernKit::VibeTavern::ToolCalling::Presets.provider_defaults("openai")
    assert_equal false, cfg.dig(:request_overrides, :parallel_tool_calls)
  end

  def test_content_tag_tool_call_fallback_preset_is_opt_in
    cfg = TavernKit::VibeTavern::ToolCalling::Presets.content_tag_tool_call_fallback
    assert_equal ["assistant_content_tool_call_tags_to_tool_calls"], cfg[:response_transforms]
  end

  def test_openai_compatible_reliability_can_enable_content_tag_fallback
    cfg =
      TavernKit::VibeTavern::ToolCalling::Presets.openai_compatible_reliability(
        enable_content_tag_fallback: true,
      )

    response_transforms = Array(cfg[:response_transforms]).map(&:to_s)
    assert_includes response_transforms, "assistant_content_tool_call_tags_to_tool_calls"
  end
end
