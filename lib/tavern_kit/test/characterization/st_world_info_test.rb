# frozen_string_literal: true

require "test_helper"

class StWorldInfoTest < Minitest::Test
  def pending!(reason)
    skip("Pending ST parity: #{reason}")
  end

  def test_insertion_strategy_ordering
    pending!("Character/global ordering + chat/persona precedence")

    entries = TavernKit::SillyTavern::WorldInfo.sort_entries(
      global: [{ id: "g1" }],
      character: [{ id: "c1" }],
      chat: [{ id: "chat1" }],
      persona: [{ id: "p1" }],
      strategy: :character_first
    )

    assert_equal %w[chat1 p1 c1 g1], entries.map { |e| e[:id] }
  end

  def test_selective_logic
    pending!("Selective logic AND/NOT variants")

    entry = {
      keys: ["dragon"],
      keysecondary: ["cave"],
      selective: true,
      selective_logic: :and_all,
    }

    scan = TavernKit::SillyTavern::WorldInfo.match_entry(entry, "dragon appears")
    assert_equal false, scan
  end

  def test_budget_cap
    pending!("Budget percent with cap, ignore_budget bypass")

    result = TavernKit::SillyTavern::WorldInfo.apply_budget(
      entries: [{ id: "a", tokens: 50 }, { id: "b", tokens: 60 }],
      max_context: 1000,
      budget_percent: 1,
      budget_cap: 5
    )

    assert_equal ["a"], result.map { |e| e[:id] }
  end

  def test_recursion_and_delay
    pending!("Recursive scan + delay_until_recursion + exclude_recursion")

    entry = { id: "a", delay_until_recursion: 1, exclude_recursion: false }
    state = TavernKit::SillyTavern::WorldInfo.scan_state(entry, recursion: true)

    assert_equal :eligible, state
  end
end
