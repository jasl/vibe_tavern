# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::PromptBuilder::Steps::CompilationTest < Minitest::Test
  def run_compilation(ctx)
    TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Compilation, name: :compilation
    end.call(ctx)
  end

  def test_compiles_pinned_groups_and_relative_entries_in_order
    ctx = TavernKit::PromptBuilder::State.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob"),
      preset: TavernKit::SillyTavern::Preset.new,
      history: [],
      user_message: "",
    )

    ctx.prompt_entries = [
      TavernKit::PromptBuilder::PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
      TavernKit::PromptBuilder::PromptEntry.new(id: "custom_rel", pinned: false, role: :system, position: :relative, content: "X"),
      TavernKit::PromptBuilder::PromptEntry.new(id: "custom_chat", pinned: false, role: :system, position: :in_chat, depth: 1, content: "Y"),
      TavernKit::PromptBuilder::PromptEntry.new(id: "chat_history", pinned: true, role: :system),
    ]

    ctx.pinned_groups = {
      "main_prompt" => [TavernKit::PromptBuilder::Block.new(role: :system, content: "M", slot: :main_prompt, token_budget_group: :system, removable: false)],
      "chat_history" => [TavernKit::PromptBuilder::Block.new(role: :user, content: "H", slot: :chat_history, token_budget_group: :history, removable: true)],
    }

    run_compilation(ctx)

    assert_equal ["M", "X", "H"], ctx.blocks.map(&:content)

    custom = ctx.blocks[1]
    assert_equal :custom_rel, custom.slot
    assert_equal :system, custom.token_budget_group
    assert_equal false, custom.removable?
    assert_equal :prompt_entry, custom.metadata[:source]
    assert_equal "custom_rel", custom.metadata[:prompt_entry_id]
  end
end
