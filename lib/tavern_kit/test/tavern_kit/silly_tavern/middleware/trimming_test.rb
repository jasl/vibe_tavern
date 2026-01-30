# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Middleware::TrimmingTest < Minitest::Test
  class CharEstimator
    def estimate(text, model_hint: nil)
      text.to_s.length
    end
  end

  def run_trimming(ctx)
    TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::Trimming, name: :trimming
    end.call(ctx)
  end

  def test_trimming_disables_removable_blocks_and_builds_final_plan
    preset = TavernKit::SillyTavern::Preset.new(
      context_window_tokens: 3,
      reserved_response_tokens: 0,
      message_token_overhead: 0,
    )

    ctx = TavernKit::Prompt::Context.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob"),
      preset: preset,
      history: [],
      user_message: "",
      dialect: :openai,
      token_estimator: CharEstimator.new,
    )

    system_block = TavernKit::Prompt::Block.new(
      role: :system,
      content: "AAA",
      token_budget_group: :system,
      removable: false,
    )
    history_block = TavernKit::Prompt::Block.new(
      role: :assistant,
      content: "BBBB",
      token_budget_group: :history,
      removable: true,
    )

    ctx.blocks = [system_block, history_block]
    ctx.llm_options = { assistant_prefill: "PREFILL" }

    ctx.instrumenter = TavernKit::Prompt::Instrumenter::TraceCollector.new

    run_trimming(ctx)

    assert_equal false, ctx.blocks[1].enabled?
    assert_equal 1, ctx.trim_report.eviction_count

    assert ctx.plan
    assert_equal ctx.blocks.map(&:enabled?), ctx.plan.blocks.map(&:enabled?)
    assert ctx.plan.trim_report
    assert ctx.plan.trace
    assert_equal({ assistant_prefill: "PREFILL" }, ctx.plan.llm_options)

    assert_equal ctx.plan.fingerprint(dialect: :openai), ctx.plan.trace.fingerprint
  end
end
