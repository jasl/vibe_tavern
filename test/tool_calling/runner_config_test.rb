# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/runner_config"

class RunnerConfigTest < Minitest::Test
  def test_build_injects_language_policy_config_into_pipeline_stage
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        runtime: { language_policy: { enabled: true, target_lang: "ja" } },
      )

    stage = runner_config.pipeline[:language_policy]
    refute_nil stage

    config = stage.options.fetch(:config)
    assert_instance_of TavernKit::VibeTavern::LanguagePolicy::Config, config
    assert_equal true, config.enabled
    assert_equal "ja-JP", config.target_lang
  end

  def test_build_parses_output_tags_config_from_runtime
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        runtime: {
          output_tags: {
            enabled: true,
            rules: [{ tag: "lang", action: :strip }],
            sanitizers: { lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip } },
          },
        },
      )

    config = runner_config.output_tags
    assert_instance_of TavernKit::VibeTavern::OutputTags::Config, config
    assert_equal true, config.enabled
    assert_equal :strip, config.rules.first.action
  end

  def test_build_merges_middleware_options_with_injected_language_policy_config
    custom_builder =
      lambda do |_target_lang, style_hint:, special_tags:|
        "custom #{style_hint.inspect} #{special_tags.inspect}"
      end

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        runtime: { language_policy: { enabled: true, target_lang: "zh-CN" } },
        middleware_options: { language_policy: { policy_text_builder: custom_builder } },
      )

    stage = runner_config.pipeline[:language_policy]
    refute_nil stage

    assert_equal custom_builder, stage.options.fetch(:policy_text_builder)
    assert_instance_of TavernKit::VibeTavern::LanguagePolicy::Config, stage.options.fetch(:config)
  end
end
