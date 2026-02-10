# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/runner_config"

class RunnerConfigTest < Minitest::Test
  def test_build_injects_language_policy_config_into_pipeline_stage
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: { language_policy: { enabled: true, target_lang: "ja" } },
      )

    entry = runner_config.pipeline[:language_policy]
    refute_nil entry

    assert_equal true, entry.options.fetch(:enabled)
    assert_equal "ja-JP", entry.options.fetch(:target_lang)
    assert_equal TavernKit::VibeTavern::PromptBuilder::Steps::LanguagePolicy::Config, entry.config_class
    assert_instance_of TavernKit::VibeTavern::PromptBuilder::Steps::LanguagePolicy::Config, entry.default_config
  end

  def test_build_parses_output_tags_config_from_context
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: {
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

  def test_build_normalizes_context_to_strict_context
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: { language_policy: { enabled: true, target_lang: "ja" } },
      )

    context = runner_config.context
    assert_instance_of TavernKit::PromptBuilder::Context, context
    assert_equal true, context.strict_keys?
    assert_raises(KeyError) { context.typo = true }
  end

  def test_build_merges_step_options_with_injected_language_policy_config
    custom_builder =
      lambda do |_target_lang, style_hint:, special_tags:|
        "custom #{style_hint.inspect} #{special_tags.inspect}"
      end

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: { language_policy: { enabled: true, target_lang: "zh-CN" } },
        step_options: { language_policy: { policy_text_builder: custom_builder } },
      )

    entry = runner_config.pipeline[:language_policy]
    refute_nil entry

    assert_equal custom_builder, entry.options.fetch(:policy_text_builder)
    assert_equal "zh-CN", entry.options.fetch(:target_lang)
    assert_instance_of TavernKit::VibeTavern::PromptBuilder::Steps::LanguagePolicy::Config, entry.default_config
    assert_equal custom_builder, entry.default_config.policy_text_builder
  end
end
