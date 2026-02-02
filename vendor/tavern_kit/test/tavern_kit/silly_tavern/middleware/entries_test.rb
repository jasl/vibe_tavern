# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Middleware::EntriesTest < Minitest::Test
  def build_ctx(preset:, **overrides)
    ctx = TavernKit::Prompt::Context.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob", persona: "Persona"),
      preset: preset,
      history: [],
      user_message: "hi",
      generation_type: :normal,
    )
    overrides.each { |k, v| ctx.public_send(:"#{k}=", v) }
    ctx
  end

  def run_entries(ctx)
    TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::Hooks, name: :hooks
      use TavernKit::SillyTavern::Middleware::Entries, name: :entries
    end.call(ctx)
  end

  def test_filters_by_enabled_triggers_and_conditions
    preset = TavernKit::SillyTavern::Preset.new(
      prompt_entries: [
        TavernKit::Prompt::PromptEntry.new(id: "a", enabled: false),
        TavernKit::Prompt::PromptEntry.new(id: "b", triggers: [:continue]),
        TavernKit::Prompt::PromptEntry.new(id: "c", conditions: { turns: { min: 3 } }),
        TavernKit::Prompt::PromptEntry.new(id: "d"),
      ],
    )

    ctx = build_ctx(preset: preset, turn_count: 2, generation_type: :normal)
    run_entries(ctx)
    assert_equal %w[d], ctx.prompt_entries.map(&:id)

    ctx = build_ctx(preset: preset, turn_count: 3, generation_type: :continue)
    run_entries(ctx)
    assert_equal %w[b c d], ctx.prompt_entries.map(&:id)
  end

  def test_forces_chat_history_to_relative
    preset = TavernKit::SillyTavern::Preset.new(
      prompt_entries: [
        TavernKit::Prompt::PromptEntry.new(id: "chat_history", pinned: true, position: :in_chat, depth: 2),
      ],
    )

    ctx = build_ctx(preset: preset)
    run_entries(ctx)

    entry = ctx.prompt_entries.first
    assert_equal "chat_history", entry.id
    assert_equal :relative, entry.position
  end

  def test_forces_chat_examples_to_relative
    preset = TavernKit::SillyTavern::Preset.new(
      prompt_entries: [
        TavernKit::Prompt::PromptEntry.new(id: "chat_examples", pinned: true, position: :in_chat, depth: 2),
      ],
    )

    ctx = build_ctx(preset: preset)
    run_entries(ctx)

    entry = ctx.prompt_entries.first
    assert_equal "chat_examples", entry.id
    assert_equal :relative, entry.position
  end

  def test_forces_post_history_instructions_to_end
    preset = TavernKit::SillyTavern::Preset.new(
      prompt_entries: [
        TavernKit::Prompt::PromptEntry.new(id: "post_history_instructions", pinned: true),
        TavernKit::Prompt::PromptEntry.new(id: "main_prompt", pinned: true),
        TavernKit::Prompt::PromptEntry.new(id: "customThing"),
      ],
    )

    ctx = build_ctx(preset: preset)
    run_entries(ctx)

    assert_equal "post_history_instructions", ctx.prompt_entries.last.id
  end
end
