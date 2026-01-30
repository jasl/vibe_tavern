# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Middleware::InjectionTest < Minitest::Test
  def run_pipeline(ctx)
    TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::PinnedGroups, name: :pinned_groups
      use TavernKit::SillyTavern::Middleware::Injection, name: :injection
    end.call(ctx)
  end

  def base_ctx(character:, preset:, prompt_entries:, lore_result: nil, injection_registry: nil, **attrs)
    ctx = TavernKit::Prompt::Context.new(
      character: character,
      user: TavernKit::User.new(name: "Bob", persona: "Persona"),
      preset: preset,
      history: [],
      user_message: "hi",
    )
    ctx.prompt_entries = prompt_entries
    ctx.lore_result = lore_result || TavernKit::Lore::Result.new(activated_entries: [], total_tokens: 0, trim_report: nil)
    ctx.injection_registry = injection_registry || TavernKit::SillyTavern::InjectionRegistry.new
    attrs.each { |k, v| ctx.public_send(:"#{k}=", v) }
    ctx
  end

  def test_before_and_after_injections_wrap_main_prompt_for_chat_dialects
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new(main_prompt: "BASE", prefer_char_prompt: false)
    prompt_entries = [
      TavernKit::Prompt::PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
    ]

    registry = TavernKit::SillyTavern::InjectionRegistry.new
    registry.register(id: "a_before", content: "BEFORE", position: :before)
    registry.register(id: "z_after", content: "AFTER", position: :after)

    ctx = base_ctx(character: character, preset: preset, prompt_entries: prompt_entries, injection_registry: registry)
    run_pipeline(ctx)

    assert_equal ["BEFORE", "BASE", "AFTER"], ctx.pinned_groups.fetch("main_prompt").map(&:content)
  end

  def test_in_chat_injection_skips_header_and_marks_injected_blocks
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new(new_chat_prompt: "HEADER", prefer_char_prompt: false)
    prompt_entries = [
      TavernKit::Prompt::PromptEntry.new(id: "chat_history", pinned: true, role: :system),
    ]

    registry = TavernKit::SillyTavern::InjectionRegistry.new
    registry.register(id: "sys_d0", content: "INJ", position: :chat, depth: 0, role: :system)

    ctx = base_ctx(
      character: character,
      preset: preset,
      prompt_entries: prompt_entries,
      injection_registry: registry,
      history: [{ role: :user, content: "m1" }, { role: :assistant, content: "m2" }],
      user_message: "m3",
    )

    run_pipeline(ctx)

    blocks = ctx.pinned_groups.fetch("chat_history")

    assert_equal "HEADER", blocks.first.content
    assert_equal :system, blocks.first.token_budget_group
    assert_equal false, blocks.first.removable?

    assert_equal ["HEADER", "m1", "m2", "m3", "INJ"], blocks.map(&:content)

    injected = blocks.last
    assert_equal :system, injected.token_budget_group
    assert_equal false, injected.removable?
    assert_equal true, injected.metadata[:injected]

    # Original message metadata should be preserved for debugging.
    assert_equal :user_message, blocks[-2].metadata[:source]
  end

  def test_in_chat_prompt_entries_are_injected
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new(new_chat_prompt: "", prefer_char_prompt: false)
    prompt_entries = [
      TavernKit::Prompt::PromptEntry.new(id: "chat_history", pinned: true, role: :system),
      TavernKit::Prompt::PromptEntry.new(id: "custom_chat", pinned: false, role: :system, position: :in_chat, depth: 1, content: "CUSTOM"),
    ]

    ctx = base_ctx(
      character: character,
      preset: preset,
      prompt_entries: prompt_entries,
      history: [{ role: :user, content: "m1" }, { role: :assistant, content: "m2" }],
      user_message: "m3",
    )

    run_pipeline(ctx)

    blocks = ctx.pinned_groups.fetch("chat_history")
    assert_equal ["m1", "m2", "CUSTOM", "m3"], blocks.map(&:content)
  end

  def test_authors_note_rewrites_persona_and_wraps_world_info_entries
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new(
      main_prompt: "BASE",
      prefer_char_prompt: false,
      authors_note: "AN",
      authors_note_frequency: 1,
      authors_note_position: :after,
    )
    prompt_entries = [
      TavernKit::Prompt::PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
      TavernKit::Prompt::PromptEntry.new(id: "authors_note", pinned: true, role: :system),
    ]

    lore = TavernKit::Lore::Result.new(
      activated_entries: [
        TavernKit::Lore::Entry.new(keys: ["x"], content: "TOP", insertion_order: 10, id: "t", position: "top_of_an"),
        TavernKit::Lore::Entry.new(keys: ["x"], content: "BOTTOM", insertion_order: 9, id: "b", position: "bottom_of_an"),
      ],
      total_tokens: 0,
      trim_report: nil,
    )

    ctx = base_ctx(character: character, preset: preset, prompt_entries: prompt_entries, lore_result: lore, turn_count: 1)
    ctx[:persona_position] = :top_an

    run_pipeline(ctx)

    blocks = ctx.pinned_groups.fetch("main_prompt")
    assert_equal ["BASE", "TOP\nPersona\nAN\nBOTTOM"], blocks.map(&:content)
  end

  def test_text_dialect_story_string_consumes_anchors_and_clears_replaced_groups
    character = TavernKit::Character.create(name: "Alice", description: "DESC", personality: "P", scenario: "S")
    preset = TavernKit::SillyTavern::Preset.new(
      main_prompt: "BASE",
      prefer_char_prompt: false,
      context_template: TavernKit::SillyTavern::ContextTemplate.new(
        story_string: "{{anchorBefore}}--{{description}}--{{anchorAfter}}",
        story_string_position: :in_prompt,
      ),
    )

    prompt_entries = %w[
      main_prompt
      world_info_before_char_defs
      persona_description
      character_description
      character_personality
      scenario
      world_info_after_char_defs
    ].map { |id| TavernKit::Prompt::PromptEntry.new(id: id, pinned: true, role: :system) }

    registry = TavernKit::SillyTavern::InjectionRegistry.new
    registry.register(id: "a_before", content: "B", position: :before)
    registry.register(id: "z_after", content: "A", position: :after)

    ctx = base_ctx(
      character: character,
      preset: preset,
      prompt_entries: prompt_entries,
      injection_registry: registry,
      dialect: :text,
    )

    run_pipeline(ctx)

    assert_equal ["B--DESC--A\n"], ctx.pinned_groups.fetch("main_prompt").map(&:content)

    %w[
      persona_description
      character_description
      character_personality
      scenario
      world_info_before_char_defs
      world_info_after_char_defs
    ].each do |key|
      assert_equal [], ctx.pinned_groups.fetch(key), "expected #{key} to be cleared for story string"
    end
  end

  def test_text_dialect_story_string_in_chat_injects_and_removes_main_prompt
    character = TavernKit::Character.create(name: "Alice", description: "DESC", personality: "P", scenario: "S")
    preset = TavernKit::SillyTavern::Preset.new(
      new_chat_prompt: "",
      main_prompt: "BASE",
      prefer_char_prompt: false,
      context_template: TavernKit::SillyTavern::ContextTemplate.new(
        story_string: "SS",
        story_string_position: :in_chat,
        story_string_depth: 0,
        story_string_role: :system,
      ),
    )

    prompt_entries = [
      TavernKit::Prompt::PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
      TavernKit::Prompt::PromptEntry.new(id: "chat_history", pinned: true, role: :system),
    ]

    ctx = base_ctx(
      character: character,
      preset: preset,
      prompt_entries: prompt_entries,
      dialect: :text,
      history: [{ role: :user, content: "m1" }],
      user_message: "m2",
    )

    run_pipeline(ctx)

    assert_equal [], ctx.pinned_groups.fetch("main_prompt")

    blocks = ctx.pinned_groups.fetch("chat_history")
    assert_equal ["m1", "m2", "SS"], blocks.map(&:content)
  end

  def test_ephemeral_injections_are_not_auto_removed
    character = TavernKit::Character.create(name: "Alice")
    preset = TavernKit::SillyTavern::Preset.new(main_prompt: "BASE", prefer_char_prompt: false)
    prompt_entries = [
      TavernKit::Prompt::PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
    ]

    registry = TavernKit::SillyTavern::InjectionRegistry.new
    registry.register(id: "persist", content: "P", position: :after, ephemeral: false)
    registry.register(id: "temp", content: "T", position: :after, ephemeral: true)

    ctx = base_ctx(character: character, preset: preset, prompt_entries: prompt_entries, injection_registry: registry)
    run_pipeline(ctx)

    ids = registry.each.map(&:id)
    assert_includes ids, "persist"
    assert_includes ids, "temp"
    assert_equal ["temp"], registry.ephemeral_ids
  end
end
