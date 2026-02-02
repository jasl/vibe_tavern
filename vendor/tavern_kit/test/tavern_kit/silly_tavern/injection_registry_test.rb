# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::InjectionRegistryTest < Minitest::Test
  def test_from_st_json_coerces_positions_and_sorts_by_id
    fixture = TavernKitTest::Fixtures.json("silly_tavern/injects/basic.json")

    registry = TavernKit::SillyTavern::InjectionRegistry.from_st_json(fixture)
    entries = registry.each.to_a

    assert entries.all? { |e| e.is_a?(TavernKit::InjectionRegistry::Entry) }
    assert_equal entries.map(&:id).sort, entries.map(&:id)

    alpha = entries.find { |e| e.id == "alpha" }
    assert_equal :after, alpha.position
    assert_equal :system, alpha.role
    assert_equal 4, alpha.depth
    assert_equal false, alpha.scan?

    beta = entries.find { |e| e.id == "beta" }
    assert_equal :before, beta.position

    gamma = entries.find { |e| e.id == "gamma" }
    assert_equal :chat, gamma.position
    assert_equal 1, gamma.depth
    assert gamma.scan?
  end

  def test_filter_string_is_treated_as_external_input_and_is_tolerant
    fixture = TavernKitTest::Fixtures.json("silly_tavern/injects/basic.json")

    registry = TavernKit::SillyTavern::InjectionRegistry.from_st_json(fixture)
    delta = registry.each.find { |e| e.id == "delta" }

    ctx = TavernKit::Prompt::Context.new
    ctx.warning_handler = nil

    assert delta.active_for?(ctx)
    assert_includes ctx.warnings.first, "Unsupported ST filter closure ignored"
  end
end
