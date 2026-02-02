# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Lore::TimedEffectsTest < Minitest::Test
  def test_sets_and_reads_sticky_effect
    entry = timed_entries.fetch("0") # sticky: 3
    state = {}

    # ST ordering: timed effects are checked at the start of a scan,
    # then newly-activated entries are persisted at the end.
    effects = TavernKit::SillyTavern::Lore::TimedEffects.new(
      turn_count: 10,
      entries: [entry],
      timed_state: state,
    )
    effects.check!.set_effects!([entry])

    assert_equal 1, state.size
    assert_equal 13, state.fetch("0").fetch(:sticky).fetch(:end_turn)

    next_turn = TavernKit::SillyTavern::Lore::TimedEffects.new(
      turn_count: 11,
      entries: [entry],
      timed_state: state,
    ).check!
    assert next_turn.sticky_active?("0")
  end

  def test_removes_non_protected_effect_when_chat_not_advanced
    entry = timed_entries.fetch("0")
    state = {
      "0" => {
        sticky: { start_turn: 10, end_turn: 13, protected: false },
      },
    }

    effects = TavernKit::SillyTavern::Lore::TimedEffects.new(
      turn_count: 10,
      entries: [entry],
      timed_state: state,
    ).check!

    refute effects.sticky_active?("0")
    assert_equal({}, state.fetch("0"))
  end

  def test_sticky_end_starts_cooldown_when_configured
    entry = timed_entries.fetch("3") # sticky: 2, cooldown: 3
    state = {
      "3" => {
        sticky: { start_turn: 5, end_turn: 7, protected: true },
      },
    }

    effects = TavernKit::SillyTavern::Lore::TimedEffects.new(
      turn_count: 7,
      entries: [entry],
      timed_state: state,
    ).check!

    refute effects.sticky_active?("3")
    assert effects.cooldown_active?("3")

    cooldown = state.fetch("3").fetch(:cooldown)
    assert_equal 7, cooldown.fetch(:start_turn)
    assert_equal 10, cooldown.fetch(:end_turn)
    assert_equal true, cooldown.fetch(:protected)
  end

  def test_delay_is_computed_from_entry_field
    entry = timed_entries.fetch("2") # delay: 2
    state = {}

    effects1 = TavernKit::SillyTavern::Lore::TimedEffects.new(
      turn_count: 1,
      entries: [entry],
      timed_state: state,
    ).check!
    assert effects1.delay_active?(entry)

    effects2 = TavernKit::SillyTavern::Lore::TimedEffects.new(
      turn_count: 2,
      entries: [entry],
      timed_state: state,
    ).check!
    refute effects2.delay_active?(entry)
  end

  private

  def timed_entries
    @timed_entries ||= begin
      raw = TavernKitTest::Fixtures.json("silly_tavern", "world_info", "timed_effects.json")
      book = TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(raw)
      book.entries.each_with_object({}) { |e, map| map[e.id] = e }
    end
  end
end
