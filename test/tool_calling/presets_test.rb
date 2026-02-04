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
        request_overrides: { "provider" => { order: ["p2"] }, "top_p" => 0.9 },
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
end
