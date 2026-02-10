# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::PromptBuilder::Steps::PinnedGroupsTest < Minitest::Test
  def run_pinned_groups(ctx)
    TavernKit::PromptBuilder::Pipeline.new do
      use_step :pinned_groups, TavernKit::SillyTavern::PromptBuilder::Steps::PinnedGroups
    end.call(ctx)
  end

  def base_ctx(character:, preset:, prompt_entries:, lore_result: nil, **attrs)
    ctx = TavernKit::PromptBuilder::State.new(
      character: character,
      user: TavernKit::User.new(name: "Bob", persona: "Persona"),
      preset: preset,
      history: [],
      user_message: "hi",
    )
    ctx.prompt_entries = prompt_entries
    ctx.lore_result = lore_result || TavernKit::Lore::Result.new(activated_entries: [], total_tokens: 0, trim_report: nil)
    attrs.each { |k, v| ctx.public_send(:"#{k}=", v) }
    ctx
  end

  def test_main_prompt_prefers_character_system_prompt_when_enabled
    character = TavernKit::Character.create(name: "Alice", system_prompt: "CHAR_MAIN")
    preset = TavernKit::SillyTavern::Preset.new(main_prompt: "PRESET_MAIN", prefer_char_prompt: true)
    entry = TavernKit::PromptBuilder::PromptEntry.new(id: "main_prompt", pinned: true, role: :system)

    ctx = base_ctx(character: character, preset: preset, prompt_entries: [entry])
    run_pinned_groups(ctx)

    assert_equal "CHAR_MAIN", ctx.pinned_groups.fetch("main_prompt").first.content
  end

  def test_persona_description_only_emits_for_in_prompt_position
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new
    entry = TavernKit::PromptBuilder::PromptEntry.new(id: "persona_description", pinned: true, role: :system)

    ctx = base_ctx(character: character, preset: preset, prompt_entries: [entry])
    ctx[:persona_position] = :at_depth
    run_pinned_groups(ctx)
    assert_equal [], ctx.pinned_groups.fetch("persona_description")

    ctx = base_ctx(character: character, preset: preset, prompt_entries: [entry])
    ctx[:persona_position] = :in_prompt
    run_pinned_groups(ctx)
    assert_equal ["Persona"], ctx.pinned_groups.fetch("persona_description").map(&:content)
  end

  def test_character_personality_uses_format_only_when_personality_present
    preset = TavernKit::SillyTavern::Preset.new(personality_format: "P({{personality}})")
    entry = TavernKit::PromptBuilder::PromptEntry.new(id: "character_personality", pinned: true, role: :system)

    ctx = base_ctx(character: TavernKit::Character.create(name: "Alice", personality: "Kind"), preset: preset, prompt_entries: [entry])
    run_pinned_groups(ctx)
    assert_equal ["P({{personality}})"], ctx.pinned_groups.fetch("character_personality").map(&:content)

    ctx = base_ctx(character: TavernKit::Character.create(name: "Alice", personality: ""), preset: preset, prompt_entries: [entry])
    run_pinned_groups(ctx)
    assert_equal [], ctx.pinned_groups.fetch("character_personality")
  end

  def test_world_info_groups_apply_wi_format_and_ordering
    preset = TavernKit::SillyTavern::Preset.new(wi_format: "WI({0})")
    entry = TavernKit::PromptBuilder::PromptEntry.new(id: "world_info_before_char_defs", pinned: true, role: :system)

    lore = TavernKit::Lore::Result.new(
      activated_entries: [
        TavernKit::Lore::Entry.new(keys: ["x"], content: "A", insertion_order: 10, id: "1", position: "before_char_defs"),
        TavernKit::Lore::Entry.new(keys: ["x"], content: "B", insertion_order: 5, id: "2", position: "before_char_defs"),
      ],
      total_tokens: 0,
      trim_report: nil,
    )

    ctx = base_ctx(character: TavernKit::Character.create(name: "Alice"), preset: preset, prompt_entries: [entry], lore_result: lore)
    run_pinned_groups(ctx)

    assert_equal ["WI(B\nA)"], ctx.pinned_groups.fetch("world_info_before_char_defs").map(&:content)
  end

  def test_chat_history_includes_new_chat_and_user_message
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new(new_chat_prompt: "NEW_CHAT", send_if_empty: "SEND")
    entry = TavernKit::PromptBuilder::PromptEntry.new(id: "chat_history", pinned: true, role: :system)

    ctx = base_ctx(character: character, preset: preset, prompt_entries: [entry], history: [{ role: :assistant, content: "A1" }], user_message: "U1")
    run_pinned_groups(ctx)

    blocks = ctx.pinned_groups.fetch("chat_history")
    assert_equal "NEW_CHAT", blocks.first.content
    assert_equal :system, blocks.first.token_budget_group
    assert_equal "U1", blocks.last.content
    assert_equal :user, blocks.last.role

    ctx = base_ctx(character: character, preset: preset, prompt_entries: [entry], history: [{ role: :assistant, content: "A1" }], user_message: "")
    run_pinned_groups(ctx)

    blocks = ctx.pinned_groups.fetch("chat_history")
    assert_equal "SEND", blocks.last.content
    assert_equal :user, blocks.last.role
    assert_equal :send_if_empty, blocks.last.metadata[:source]
  end

  def test_send_if_empty_is_not_emitted_for_continue_builds
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new(new_chat_prompt: "", send_if_empty: "SEND")
    entry = TavernKit::PromptBuilder::PromptEntry.new(id: "chat_history", pinned: true, role: :system)

    ctx = base_ctx(
      character: character,
      preset: preset,
      prompt_entries: [entry],
      history: [{ role: :assistant, content: "A1" }],
      user_message: "",
      generation_type: :continue,
    )
    run_pinned_groups(ctx)

    blocks = ctx.pinned_groups.fetch("chat_history")
    assert_equal ["A1"], blocks.map(&:content)
  end

  def test_chat_examples_emits_header_and_bundles
    character = TavernKit::Character.create(name: "Alice", mes_example: "<START>\nExample 1")
    preset = TavernKit::SillyTavern::Preset.new(new_example_chat_prompt: "NEW_EXAMPLE")
    entry = TavernKit::PromptBuilder::PromptEntry.new(id: "chat_examples", pinned: true, role: :system)

    ctx = base_ctx(character: character, preset: preset, prompt_entries: [entry])
    run_pinned_groups(ctx)

    blocks = ctx.pinned_groups.fetch("chat_examples")
    assert_equal "NEW_EXAMPLE", blocks.first.content
    assert_equal "examples:header", blocks.first.metadata[:eviction_bundle]
    assert_equal "examples:dialogue:0", blocks.last.metadata[:eviction_bundle]
  end
end
