# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::MaxTokensStepTest < Minitest::Test
  module BuildPlanStep
    extend TavernKit::PromptBuilder::Step

    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "build_plan step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "build_plan step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "build_plan step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      blocks = []
      blocks << TavernKit::PromptBuilder::Block.new(role: :user, content: ctx.user_message.to_s) if ctx.user_message
      ctx.plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)
    end
  end

  module BuildTwoMessagesPlanStep
    extend TavernKit::PromptBuilder::Step

    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "build_two_messages_plan step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "build_two_messages_plan step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "build_two_messages_plan step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      blocks = [
        TavernKit::PromptBuilder::Block.new(role: :user, content: "hi"),
        TavernKit::PromptBuilder::Block.new(role: :user, content: "ok"),
      ]
      ctx.plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)
    end
  end

  module BuildOneMessageWithMetadataPlanStep
    extend TavernKit::PromptBuilder::Step

    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "build_one_message_with_metadata_plan step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "build_one_message_with_metadata_plan step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "build_one_message_with_metadata_plan step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      blocks = [
        TavernKit::PromptBuilder::Block.new(
          role: :assistant,
          content: "ok",
          message_metadata: {
            tool_calls: [
              {
                id: "call_123",
                type: "function",
                function: { name: "get_weather", arguments: "{\"location\":\"Boston, MA\"}" },
              },
            ],
          },
        ),
      ]
      ctx.plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)
    end
  end

  class CharCountEstimator
    def estimate(text, model_hint: nil)
      text.to_s.length
    end
  end

  def build_pipeline(
    max_tokens:,
    reserve_tokens: 0,
    mode: :warn,
    message_overhead_tokens: 0,
    include_message_metadata_tokens: false,
    build: :one_message
  )
    build_step =
      case build
      when :one_message then BuildPlanStep
      when :two_messages then BuildTwoMessagesPlanStep
      when :one_message_with_metadata then BuildOneMessageWithMetadataPlanStep
      else
        raise ArgumentError, "Unknown build: #{build.inspect}"
      end

    TavernKit::PromptBuilder::Pipeline.new do
      use_step :max_tokens, TavernKit::PromptBuilder::Steps::MaxTokens,
          max_tokens: max_tokens,
          reserve_tokens: reserve_tokens,
          message_overhead_tokens: message_overhead_tokens,
          include_message_metadata_tokens: include_message_metadata_tokens,
          mode: mode
      use_step :build_plan, build_step
    end
  end

  def test_warn_mode_collects_warning_when_over_limit
    pipeline = build_pipeline(max_tokens: 5, mode: :warn)
    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    pipeline.call(state)

    assert_equal 1, state.warnings.size
    assert_match(/exceeded limit/, state.warnings.first)
  end

  def test_warn_mode_no_warning_when_under_limit
    pipeline = build_pipeline(max_tokens: 6, mode: :warn)
    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    pipeline.call(state)

    assert_equal [], state.warnings
  end

  def test_message_overhead_tokens_adds_overhead_per_message
    pipeline = build_pipeline(max_tokens: 4, mode: :warn, message_overhead_tokens: 3, build: :two_messages)
    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
    )

    pipeline.call(state)

    # Messages are "hi" and "ok" => 4 content tokens + 2 * 3 overhead = 10.
    assert_equal 1, state.warnings.size
    assert_match(/exceeded limit 4/, state.warnings.first)
  end

  def test_include_message_metadata_tokens_counts_tool_calls_payload
    pipeline = build_pipeline(
      max_tokens: 10,
      mode: :warn,
      include_message_metadata_tokens: true,
      build: :one_message_with_metadata,
    )
    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
    )

    pipeline.call(state)

    # The metadata JSON is longer than the content, so it should exceed the soft cap.
    assert_equal 1, state.warnings.size
    assert_match(/exceeded limit 10/, state.warnings.first)
  end

  def test_error_mode_raises_max_tokens_exceeded_error
    pipeline = build_pipeline(max_tokens: 5, mode: :error)
    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    err = assert_raises(TavernKit::MaxTokensExceededError) do
      pipeline.call(state)
    end

    assert_equal :max_tokens, err.step
    assert_equal 6, err.estimated_tokens
    assert_equal 5, err.max_tokens
    assert_equal 0, err.reserve_tokens
    assert_equal 5, err.limit_tokens
  end

  def test_reserve_tokens_reduces_limit
    pipeline = build_pipeline(max_tokens: 10, reserve_tokens: 4, mode: :warn)
    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "1234567",
    )

    pipeline.call(state)

    assert_equal 1, state.warnings.size
    assert_match(/exceeded limit 6/, state.warnings.first)
  end

  def test_max_tokens_zero_disables_guard
    pipeline = build_pipeline(max_tokens: 0, mode: :error)
    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
    )

    pipeline.call(state)

    assert_equal [], state.warnings
  end

  def test_proc_options_are_evaluated_with_context
    pipeline = build_pipeline(
      max_tokens: ->(ctx) { ctx[:max_tokens] },
      reserve_tokens: ->(ctx) { ctx[:reserve_tokens] },
      message_overhead_tokens: ->(ctx) { ctx[:message_overhead_tokens] },
      include_message_metadata_tokens: ->(ctx) { ctx[:include_message_metadata_tokens] },
      mode: ->(ctx) { ctx[:mode] },
    )

    state = TavernKit::PromptBuilder::State.new(
      token_estimator: CharCountEstimator.new,
      warning_handler: nil,
      user_message: "hello!",
      max_tokens: 10,
      reserve_tokens: 3,
      message_overhead_tokens: 4,
      include_message_metadata_tokens: false,
      mode: :warn,
    )

    pipeline.call(state)

    # "hello!" => 6 content tokens + 1 * 4 overhead = 10, limit is 7.
    assert_equal 1, state.warnings.size
  end
end
