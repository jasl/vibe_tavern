# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Middleware::PlanAssemblyTest < Minitest::Test
  def run_plan_assembly(ctx)
    TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::PlanAssembly, name: :plan_assembly
    end.call(ctx)
  end

  def base_ctx(preset:, blocks:, generation_type: :normal, group: nil)
    TavernKit::Prompt::Context.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob"),
      preset: preset,
      history: [],
      user_message: "",
      generation_type: generation_type,
      group: group,
      blocks: blocks,
    )
  end

  def test_continue_nudge_is_appended_when_prefill_disabled
    preset = TavernKit::SillyTavern::Preset.new(
      continue_prefill: false,
      continue_nudge_prompt: "NUDGE {{char}}",
    )

    ctx = base_ctx(preset: preset, blocks: [], generation_type: :continue)
    run_plan_assembly(ctx)

    assert_equal "NUDGE Alice", ctx.blocks.last.content
    assert_equal :continue_nudge, ctx.blocks.last.metadata[:source]
  end

  def test_continue_prefill_appends_postfix_to_last_assistant_message
    preset = TavernKit::SillyTavern::Preset.new(
      continue_prefill: true,
      continue_postfix: " ",
    )

    blocks = [
      TavernKit::Prompt::Block.new(role: :assistant, content: "A", token_budget_group: :history, removable: true),
    ]

    ctx = base_ctx(preset: preset, blocks: blocks, generation_type: :continue)
    run_plan_assembly(ctx)

    assert_equal "A ", ctx.blocks.first.content
    assert_equal :continue_prefill, ctx.blocks.first.metadata[:source]
  end

  def test_claude_source_sets_assistant_prefill_request_option
    preset = TavernKit::SillyTavern::Preset.new(
      assistant_prefill: "P {{char}}",
    )

    ctx = base_ctx(preset: preset, blocks: [])
    ctx[:chat_completion_source] = "claude"
    run_plan_assembly(ctx)

    assert_equal({ assistant_prefill: "P Alice" }, ctx.plan.llm_options)
  end

  def test_continue_prefill_for_claude_prepends_assistant_prefill_to_message_content
    preset = TavernKit::SillyTavern::Preset.new(
      continue_prefill: true,
      continue_postfix: " ",
      assistant_prefill: "P",
    )

    blocks = [
      TavernKit::Prompt::Block.new(role: :assistant, content: "A", token_budget_group: :history, removable: true),
    ]

    ctx = base_ctx(preset: preset, blocks: blocks, generation_type: :continue)
    ctx[:chat_completion_source] = "claude"
    run_plan_assembly(ctx)

    assert_equal "P\n\nA ", ctx.blocks.first.content
    assert_equal({}, ctx.plan.llm_options)
  end

  def test_impersonate_for_claude_sets_assistant_impersonation_prefill_request_option
    preset = TavernKit::SillyTavern::Preset.new(
      impersonation_prompt: "IMP",
      assistant_impersonation: "AS {{user}}",
    )

    ctx = base_ctx(preset: preset, blocks: [], generation_type: :impersonate)
    ctx[:chat_completion_source] = "claude"
    run_plan_assembly(ctx)

    assert_equal({ assistant_prefill: "AS Bob" }, ctx.plan.llm_options)
  end

  def test_impersonation_prompt_is_appended_and_macro_expanded
    preset = TavernKit::SillyTavern::Preset.new(
      impersonation_prompt: "IMP {{user}}",
    )

    ctx = base_ctx(preset: preset, blocks: [], generation_type: :impersonate)
    run_plan_assembly(ctx)

    assert_equal "IMP Bob", ctx.blocks.last.content
    assert_equal :impersonation_prompt, ctx.blocks.last.metadata[:source]
  end
end
