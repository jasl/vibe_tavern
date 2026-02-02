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

  def test_continue_prefill_appends_displaced_message_for_chat_dialects
    preset = TavernKit::SillyTavern::Preset.new(
      continue_prefill: true,
      continue_postfix: " ",
    )

    ctx = base_ctx(preset: preset, blocks: [], generation_type: :continue)
    ctx[:st_continue_prefill_block] = TavernKit::Prompt::Block.new(
      role: :assistant,
      content: "A",
      slot: :chat_history,
      token_budget_group: :history,
      removable: true,
    )
    run_plan_assembly(ctx)

    assert_equal 1, ctx.blocks.size
    assert_equal "A", ctx.blocks.first.content
    assert_equal :continue_prefill, ctx.blocks.first.metadata[:source]
    assert_equal :continue_prefill, ctx.blocks.first.slot
    assert_equal :system, ctx.blocks.first.token_budget_group
    assert_equal false, ctx.blocks.first.removable?
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

    ctx = base_ctx(preset: preset, blocks: [], generation_type: :continue)
    ctx[:st_continue_prefill_block] = TavernKit::Prompt::Block.new(
      role: :assistant,
      content: "A",
      slot: :chat_history,
      token_budget_group: :history,
      removable: true,
    )
    ctx[:chat_completion_source] = "claude"
    run_plan_assembly(ctx)

    assert_equal "P\n\nA", ctx.blocks.first.content
    assert_equal({}, ctx.plan.llm_options)
  end

  def test_continue_nudge_moves_last_chat_message_after_group_nudge_for_chat_dialects
    preset = TavernKit::SillyTavern::Preset.new(
      continue_prefill: false,
      continue_nudge_prompt: "NUDGE {{char}}",
      group_nudge_prompt: "GROUP {{char}}",
    )

    blocks = [
      TavernKit::Prompt::Block.new(role: :user, content: "U", slot: :chat_history, token_budget_group: :history, removable: true),
      TavernKit::Prompt::Block.new(role: :assistant, content: "A", slot: :chat_history, token_budget_group: :history, removable: true),
      TavernKit::Prompt::Block.new(
        role: :system,
        content: "INJ",
        slot: :chat_history,
        token_budget_group: :system,
        removable: false,
        metadata: { source: :injection, injected: true },
      ),
    ]

    ctx = base_ctx(preset: preset, blocks: blocks, generation_type: :continue, group: { members: [] })
    run_plan_assembly(ctx)

    assert_equal ["U", "INJ", "GROUP Alice", "A", "NUDGE Alice"], ctx.blocks.map(&:content)
    assert_equal :group_nudge, ctx.blocks[-3].metadata[:source]
    assert_equal :continue_message, ctx.blocks[-2].metadata[:source]
    assert_equal :continue_nudge, ctx.blocks[-1].metadata[:source]
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

  def test_names_behavior_none_drops_message_names
    preset = TavernKit::SillyTavern::Preset.new(names_behavior: :none)

    blocks = [
      TavernKit::Prompt::Block.new(role: :assistant, name: "Alice", content: "A", slot: :chat_history, token_budget_group: :history, removable: true),
    ]

    ctx = base_ctx(preset: preset, blocks: blocks)
    run_plan_assembly(ctx)

    assert_nil ctx.blocks.first.name
    assert_equal "A", ctx.blocks.first.content
  end

  def test_names_behavior_default_prefixes_non_user_names_in_group_chats
    preset = TavernKit::SillyTavern::Preset.new(names_behavior: :default)

    blocks = [
      TavernKit::Prompt::Block.new(role: :user, name: "Bob", content: "U", slot: :chat_history, token_budget_group: :history, removable: true),
      TavernKit::Prompt::Block.new(role: :assistant, name: "Alice", content: "A", slot: :chat_history, token_budget_group: :history, removable: true),
    ]

    ctx = base_ctx(preset: preset, blocks: blocks, group: { members: [] })
    run_plan_assembly(ctx)

    assert_nil ctx.blocks[0].name
    assert_equal "U", ctx.blocks[0].content

    assert_nil ctx.blocks[1].name
    assert_equal "Alice: A", ctx.blocks[1].content
  end

  def test_names_behavior_content_prefixes_any_named_non_system_message
    preset = TavernKit::SillyTavern::Preset.new(names_behavior: :content)

    blocks = [
      TavernKit::Prompt::Block.new(role: :user, name: "Bob", content: "U", slot: :chat_history, token_budget_group: :history, removable: true),
      TavernKit::Prompt::Block.new(role: :assistant, name: "Alice", content: "A", slot: :chat_history, token_budget_group: :history, removable: true),
    ]

    ctx = base_ctx(preset: preset, blocks: blocks)
    run_plan_assembly(ctx)

    assert_nil ctx.blocks[0].name
    assert_equal "Bob: U", ctx.blocks[0].content

    assert_nil ctx.blocks[1].name
    assert_equal "Alice: A", ctx.blocks[1].content
  end

  def test_names_behavior_completion_sanitizes_names_and_keeps_name_field
    preset = TavernKit::SillyTavern::Preset.new(names_behavior: :completion, continue_prefill: true)

    ctx = base_ctx(preset: preset, blocks: [], generation_type: :continue)
    ctx[:st_continue_prefill_block] = TavernKit::Prompt::Block.new(
      role: :assistant,
      name: "Alice Smith",
      content: "A",
      slot: :chat_history,
      token_budget_group: :history,
      removable: true,
    )

    run_plan_assembly(ctx)

    assert_equal 1, ctx.blocks.size
    assert_equal "Alice_Smith", ctx.blocks.first.name
    assert_equal "A", ctx.blocks.first.content
  end
end
