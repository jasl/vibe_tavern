# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::PromptBuilder::Steps::LoreTest < Minitest::Test
  def build_ctx(**overrides)
    ctx = TavernKit::PromptBuilder::State.new(
      character: TavernKit::Character.create(name: "Alice", description: "A", personality: "P", scenario: "S"),
      user: TavernKit::User.new(name: "Bob", persona: "Persona"),
      preset: TavernKit::SillyTavern::Preset.new(world_info_budget: 100, world_info_budget_cap: 0),
      history: [],
      user_message: "hello",
    )

    overrides.each { |k, v| ctx.public_send(:"#{k}=", v) }
    ctx
  end

  def test_populates_scan_messages_newest_first
    ctx = build_ctx(
      history: [
        { role: "user", content: "oldest" },
        { role: "assistant", content: "newer" },
      ],
      user_message: "latest",
    )

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_equal ["latest", "newer", "oldest"], ctx.scan_messages
  end

  def test_scan_injects_include_scannable_injection_registry_entries
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["needle"],
          content: "HIT",
          id: "1",
          insertion_order: 10,
        ),
      ],
    )

    registry = TavernKit::SillyTavern::InjectionRegistry.new
    registry.register(id: "x", content: "needle", position: :after, scan: true)

    ctx = build_ctx(
      lore_books: [book],
      history: [],
      user_message: "no match",
      injection_registry: registry,
    )

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_includes ctx.scan_injects, "needle"
    assert_equal 1, ctx.lore_result.activated_entries.size
    assert_equal "HIT", ctx.lore_result.activated_entries.first.content
  end

  def test_builds_outlets_from_activated_entries
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["hello"],
          content: "OUT",
          id: "1",
          insertion_order: 10,
          position: "outlet",
          extensions: { "outlet_name" => "my_outlet" },
        ),
      ],
    )

    ctx = build_ctx(lore_books: [book], user_message: "hello")

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_equal({ "my_outlet" => "OUT" }, ctx.outlets)
  end

  def test_entry_can_match_via_character_description_when_enabled
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["elf"],
          content: "ELF_FROM_CHARACTER_DESCRIPTION",
          id: "1",
          insertion_order: 10,
          extensions: { "match_character_description" => true },
        ),
      ],
    )

    ctx =
      build_ctx(
        character: TavernKit::Character.create(name: "Alice", description: "An elf from the forest."),
        lore_books: [book],
        user_message: "No keyword in messages.",
      )

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_equal ["ELF_FROM_CHARACTER_DESCRIPTION"], ctx.lore_result.activated_entries.map(&:content)
  end

  def test_world_info_can_trigger_from_authors_note_when_allowed
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "DRAGON_FROM_AUTHORS_NOTE",
          id: "1",
          insertion_order: 10,
        ),
      ],
    )

    preset =
      TavernKit::SillyTavern::Preset.new(
        world_info_budget: 100,
        world_info_budget_cap: 0,
        authors_note: "A note that mentions dragon",
        authors_note_allow_wi_scan: true,
        authors_note_frequency: 1,
      )

    ctx = build_ctx(lore_books: [book], user_message: "No keyword in messages.", preset: preset)

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_equal ["DRAGON_FROM_AUTHORS_NOTE"], ctx.lore_result.activated_entries.map(&:content)
  end

  def test_world_info_does_not_trigger_from_authors_note_when_disallowed
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "DRAGON_FROM_AUTHORS_NOTE",
          id: "1",
          insertion_order: 10,
        ),
      ],
    )

    preset =
      TavernKit::SillyTavern::Preset.new(
        world_info_budget: 100,
        world_info_budget_cap: 0,
        authors_note: "A note that mentions dragon",
        authors_note_allow_wi_scan: false,
        authors_note_frequency: 1,
      )

    ctx = build_ctx(lore_books: [book], user_message: "No keyword in messages.", preset: preset)

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_equal [], ctx.lore_result.activated_entries.map(&:content)
  end

  def test_entry_can_match_via_character_depth_prompt_when_enabled
    book = TavernKit::Lore::Book.new(
      entries: [
        TavernKit::Lore::Entry.new(
          keys: ["dragon"],
          content: "DRAGON_FROM_DEPTH_PROMPT",
          id: "1",
          insertion_order: 10,
          extensions: { "match_character_depth_prompt" => true },
        ),
      ],
    )

    ctx =
      build_ctx(
        character:
          TavernKit::Character.create(
            name: "Alice",
            description: "A helpful assistant",
            extensions: { "depth_prompt" => { "prompt" => "A depth prompt that mentions dragon" } },
          ),
        lore_books: [book],
        user_message: "No keyword in messages.",
      )

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Hooks, name: :hooks
      use_step TavernKit::SillyTavern::PromptBuilder::Steps::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_equal ["DRAGON_FROM_DEPTH_PROMPT"], ctx.lore_result.activated_entries.map(&:content)
  end
end
