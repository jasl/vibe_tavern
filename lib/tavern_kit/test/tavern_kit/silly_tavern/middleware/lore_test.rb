# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Middleware::LoreTest < Minitest::Test
  def build_ctx(**overrides)
    ctx = TavernKit::Prompt::Context.new(
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

    pipeline = TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::Hooks, name: :hooks
      use TavernKit::SillyTavern::Middleware::Lore, name: :lore
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

    pipeline = TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::Hooks, name: :hooks
      use TavernKit::SillyTavern::Middleware::Lore, name: :lore
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

    pipeline = TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::Hooks, name: :hooks
      use TavernKit::SillyTavern::Middleware::Lore, name: :lore
    end

    pipeline.call(ctx)

    assert_equal({ "my_outlet" => "OUT" }, ctx.outlets)
  end
end
