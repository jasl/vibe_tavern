# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/directives/presets"

class DirectivesPresetsTest < Minitest::Test
  def test_merge_deep_merges_request_overrides_and_unions_transform_lists
    a =
      TavernKit::VibeTavern::Directives::Presets.directives(
        request_overrides: { temperature: 0.1, provider: { only: ["p1"] } },
        message_transforms: ["a"],
      )

    b =
      TavernKit::VibeTavern::Directives::Presets.directives(
        request_overrides: { "provider" => { order: ["p2"] }, "top_p" => 0.9 },
        message_transforms: ["b"],
      )

    merged = TavernKit::VibeTavern::Directives::Presets.merge(a, b)

    assert_equal 0.1, merged.dig(:request_overrides, :temperature)
    assert_equal 0.9, merged.dig(:request_overrides, :top_p)
    assert_equal ["p1"], merged.dig(:request_overrides, :provider, :only)
    assert_equal ["p2"], merged.dig(:request_overrides, :provider, :order)
    assert_equal ["a", "b"], merged[:message_transforms]
  end

  def test_provider_defaults_for_openrouter_enable_require_parameters_for_structured_and_disable_for_prompt_only
    cfg = TavernKit::VibeTavern::Directives::Presets.provider_defaults("openrouter", require_parameters: true)
    assert_equal true, cfg.dig(:structured_request_overrides, :provider, :require_parameters)
    assert_equal false, cfg.dig(:prompt_only_request_overrides, :provider, :require_parameters)
  end

  def test_provider_defaults_for_openrouter_can_disable_require_parameters
    cfg = TavernKit::VibeTavern::Directives::Presets.provider_defaults("openrouter", require_parameters: false)
    assert_equal({}, cfg)
  end
end
