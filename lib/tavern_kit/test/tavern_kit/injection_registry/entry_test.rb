# frozen_string_literal: true

require "test_helper"

class TavernKit::InjectionRegistry::EntryTest < Minitest::Test
  def test_defaults
    entry = TavernKit::InjectionRegistry::Entry.new(
      id: :x,
      content: 123,
      position: :after,
    )

    assert_equal "x", entry.id
    assert_equal "123", entry.content
    assert_equal :after, entry.position
    assert_equal :system, entry.role
    assert_equal 4, entry.depth
    assert_equal false, entry.scan?
    assert_equal false, entry.ephemeral?
    assert_nil entry.filter
  end

  def test_active_for_without_filter
    entry = TavernKit::InjectionRegistry::Entry.new(id: "x", content: "y", position: :after)
    assert_equal true, entry.active_for?(Object.new)
  end

  def test_active_for_with_filter
    entry = TavernKit::InjectionRegistry::Entry.new(
      id: "x",
      content: "y",
      position: :after,
      filter: ->(ctx) { ctx[:ok] == true },
    )

    ctx = TavernKit::Prompt::Context.new(ok: true)
    assert_equal true, entry.active_for?(ctx)

    ctx = TavernKit::Prompt::Context.new(ok: false)
    assert_equal false, entry.active_for?(ctx)
  end
end
