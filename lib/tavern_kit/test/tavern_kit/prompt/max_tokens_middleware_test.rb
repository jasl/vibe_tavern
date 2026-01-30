# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::MaxTokensMiddlewareTest < Minitest::Test
  class BuildPlanMiddleware < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      blocks = []
      blocks << TavernKit::Prompt::Block.new(role: :user, content: ctx.user_message.to_s) if ctx.user_message
      ctx.plan = TavernKit::Prompt::Plan.new(blocks: blocks)
    end
  end

  class BuildTwoMessagesPlanMiddleware < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      blocks = [
        TavernKit::Prompt::Block.new(role: :user, content: "hi"),
        TavernKit::Prompt::Block.new(role: :user, content: "ok"),
      ]
      ctx.plan = TavernKit::Prompt::Plan.new(blocks: blocks)
    end
  end

  class CharCountEstimator
    def estimate(text, model_hint: nil)
      text.to_s.length
    end
  end

  def build_pipeline(max_tokens:, reserve_tokens: 0, mode: :warn, message_overhead_tokens: 0, build: :one_message)
    build_middleware =
      case build
      when :one_message then BuildPlanMiddleware
      when :two_messages then BuildTwoMessagesPlanMiddleware
      else
        raise ArgumentError, "Unknown build: #{build.inspect}"
      end

    TavernKit::Prompt::Pipeline.new do
      use TavernKit::Prompt::Middleware::MaxTokensMiddleware,
          name: :max_tokens,
          max_tokens: max_tokens,
          reserve_tokens: reserve_tokens,
          message_overhead_tokens: message_overhead_tokens,
          mode: mode
      use build_middleware, name: :build_plan
    end
  end

  def test_warn_mode_collects_warning_when_over_limit
    pipeline = build_pipeline(max_tokens: 5, mode: :warn)
    ctx = TavernKit::Prompt::Context.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    pipeline.call(ctx)

    assert_equal 1, ctx.warnings.size
    assert_match(/exceeded limit/, ctx.warnings.first)
  end

  def test_warn_mode_no_warning_when_under_limit
    pipeline = build_pipeline(max_tokens: 6, mode: :warn)
    ctx = TavernKit::Prompt::Context.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    pipeline.call(ctx)

    assert_equal [], ctx.warnings
  end

  def test_message_overhead_tokens_adds_overhead_per_message
    pipeline = build_pipeline(max_tokens: 4, mode: :warn, message_overhead_tokens: 3, build: :two_messages)
    ctx = TavernKit::Prompt::Context.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
    )

    pipeline.call(ctx)

    # Messages are "hi" and "ok" => 4 content tokens + 2 * 3 overhead = 10.
    assert_equal 1, ctx.warnings.size
    assert_match(/exceeded limit 4/, ctx.warnings.first)
  end

  def test_error_mode_raises_max_tokens_exceeded_error
    pipeline = build_pipeline(max_tokens: 5, mode: :error)
    ctx = TavernKit::Prompt::Context.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    err = assert_raises(TavernKit::MaxTokensExceededError) do
      pipeline.call(ctx)
    end

    assert_equal :max_tokens, err.stage
    assert_equal 6, err.estimated_tokens
    assert_equal 5, err.max_tokens
    assert_equal 0, err.reserve_tokens
    assert_equal 5, err.limit_tokens
  end

  def test_reserve_tokens_reduces_limit
    pipeline = build_pipeline(max_tokens: 10, reserve_tokens: 4, mode: :warn)
    ctx = TavernKit::Prompt::Context.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "1234567",
    )

    pipeline.call(ctx)

    assert_equal 1, ctx.warnings.size
    assert_match(/exceeded limit 6/, ctx.warnings.first)
  end

  def test_max_tokens_zero_disables_guard
    pipeline = build_pipeline(max_tokens: 0, mode: :error)
    ctx = TavernKit::Prompt::Context.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    pipeline.call(ctx)

    assert_equal [], ctx.warnings
  end

  def test_proc_options_are_evaluated_with_context
    pipeline = build_pipeline(
      max_tokens: ->(ctx) { ctx[:max_tokens] },
      reserve_tokens: ->(ctx) { ctx[:reserve_tokens] },
      message_overhead_tokens: ->(ctx) { ctx[:message_overhead_tokens] },
      mode: ->(ctx) { ctx[:mode] },
    )

    ctx = TavernKit::Prompt::Context.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
      max_tokens: 10,
      reserve_tokens: 3,
      message_overhead_tokens: 4,
      mode: :warn,
    )

    pipeline.call(ctx)

    # "hello!" => 6 content tokens + 1 * 4 overhead = 10, limit is 7.
    assert_equal 1, ctx.warnings.size
  end
end
