# frozen_string_literal: true

require "test_helper"

class VibeTavernTokenBudgetTest < ActiveSupport::TestCase
  class FakeTokenEstimator
    def estimate(text, model_hint: nil)
      text.to_s.length
    end
  end

  test "RunnerConfig configures max_tokens step from capabilities token budget" do
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openai",
        model: "gpt-test",
        context: {
          token_estimation: {
            token_estimator: FakeTokenEstimator.new,
            model_hint: "test",
          },
        },
        capabilities_overrides: { context_window_tokens: 10, reserved_response_tokens: 2 },
      )

    entry = runner_config.pipeline[:max_tokens]
    assert_equal 10, entry.default_config.max_tokens
    assert_equal 2, entry.default_config.reserve_tokens
    assert_equal :error, entry.default_config.mode
  end

  test "RunnerConfig step_options can override the capabilities budget defaults" do
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openai",
        model: "gpt-test",
        capabilities_overrides: { context_window_tokens: 10, reserved_response_tokens: 2 },
        step_options: { max_tokens: { reserve_tokens: 3 } },
      )

    entry = runner_config.pipeline[:max_tokens]
    assert_equal 10, entry.default_config.max_tokens
    assert_equal 3, entry.default_config.reserve_tokens
  end

  test "PromptRunner rejects prompts that exceed the configured budget" do
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openai",
        model: "gpt-test",
        context: {
          token_estimation: {
            token_estimator: FakeTokenEstimator.new,
            model_hint: "test",
          },
        },
        capabilities_overrides: { context_window_tokens: 10, reserved_response_tokens: 0 },
      )

    history = [TavernKit::PromptBuilder::Message.new(role: :user, content: "a" * 50)]
    prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)

    error =
      assert_raises(TavernKit::MaxTokensExceededError) do
        prompt_runner.build_request(
          runner_config: runner_config,
          history: history,
          strict: true,
        )
      end

    assert_equal :max_tokens, error.step
  end
end
