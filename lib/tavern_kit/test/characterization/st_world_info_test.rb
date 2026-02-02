# frozen_string_literal: true

require "test_helper"

class StWorldInfoTest < Minitest::Test
  # Upstream references:
  # - resources/SillyTavern/public/scripts/world-info.js @ bba43f332
  # - docs/compatibility/sillytavern-deltas.md (tracked deltas)

  def test_insertion_strategy_ordering
    entries = TavernKit::SillyTavern::Lore::Engine.sort_entries(
      global: [{ id: "g1" }],
      character: [{ id: "c1" }],
      chat: [{ id: "chat1" }],
      persona: [{ id: "p1" }],
      strategy: :character_lore_first,
    )

    assert_equal %w[chat1 p1 c1 g1], entries.map { |e| e[:id] }
  end

  def test_selective_logic
    entry = {
      keys: ["dragon"],
      secondary_keys: ["cave"],
      selective: true,
      extensions: { selective_logic: :and_all },
    }

    scan = TavernKit::SillyTavern::Lore::Engine.match_entry(entry, "dragon appears")
    assert_equal false, scan
  end

  def test_budget_cap
    result = TavernKit::SillyTavern::Lore::Engine.apply_budget(
      entries: [{ id: "a", tokens: 50 }, { id: "b", tokens: 60 }],
      max_context: 1000,
      budget_percent: 10,
      budget_cap: 55,
    )

    assert_equal ["a"], result.map { |e| e[:id] }
  end

  def test_recursion_and_delay
    entry = { id: "a", extensions: { delay_until_recursion: 1, exclude_recursion: false } }
    state = TavernKit::SillyTavern::Lore::Engine.scan_state(entry, recursion: true)

    assert_equal :eligible, state
  end

  def test_js_regex_invalid_is_no_match_and_warns_once
    warned = {}
    warnings = []
    warner = ->(msg) { warnings << msg }

    buffer = TavernKit::SillyTavern::Lore::Engine::Buffer

    hit = buffer.match_pre_normalized?("dragon", nil, "/(", nil, case_sensitive: false, match_whole_words: true, warner: warner, warned: warned)
    assert_equal false, hit
    assert_equal 1, warnings.size

    hit_again = buffer.match_pre_normalized?("dragon", nil, "/(", nil, case_sensitive: false, match_whole_words: true, warner: warner, warned: warned)
    assert_equal false, hit_again
    assert_equal 1, warnings.size
  end

  def test_js_regex_invalid_raises_in_strict_mode_via_ctx_warn
    ctx = TavernKit::Prompt::Context.new(strict: true)
    buffer = TavernKit::SillyTavern::Lore::Engine::Buffer

    assert_raises(TavernKit::StrictModeError) do
      buffer.match_pre_normalized?("dragon", nil, "/(", nil, case_sensitive: false, match_whole_words: true, warner: ctx.method(:warn), warned: {})
    end
  end
end
