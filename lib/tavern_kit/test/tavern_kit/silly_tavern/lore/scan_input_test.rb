# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Lore::ScanInputTest < Minitest::Test
  def test_inherits_from_base_scan_input
    input = build_input
    assert_kind_of TavernKit::Lore::ScanInput, input
  end

  def test_basic_attributes
    input = build_input(
      messages: ["msg1", "msg2"],
      budget: 1500
    )

    assert_equal ["msg1", "msg2"], input.messages
    assert_equal 1500, input.budget
  end

  def test_default_values
    input = build_input

    assert_equal({}, input.scan_context)
    assert_equal [], input.scan_injects
    assert_equal :normal, input.trigger
    assert_equal({}, input.timed_state)
    assert_nil input.character_name
    assert_equal [], input.character_tags
    assert_equal [], input.forced_activations
    assert_equal 0, input.min_activations
    assert_equal 0, input.min_activations_depth_max
    assert_equal 0, input.turn_count
  end

  def test_scan_context_normalization
    input = build_input(
      scan_context: {
        "persona_description" => "A brave knight",
        :character_description => "Tall and strong",
        "invalid_key" => "ignored",
      }
    )

    assert_equal "A brave knight", input.scan_context[:persona_description]
    assert_equal "Tall and strong", input.scan_context[:character_description]
    refute input.scan_context.key?(:invalid_key)
  end

  def test_scan_context_frozen
    input = build_input(scan_context: { persona_description: "test" })
    assert input.scan_context.frozen?
  end

  def test_trigger_coerced_to_symbol
    input = build_input(trigger: "continue")
    assert_equal :continue, input.trigger
  end

  def test_context_value
    input = build_input(
      scan_context: {
        persona_description: "Knight persona",
        scenario: "In a castle",
      }
    )

    assert_equal "Knight persona", input.context_value(:persona_description)
    assert_equal "In a castle", input.context_value(:scenario)
    assert_nil input.context_value(:character_description)
  end

  def test_context_values
    input = build_input(
      scan_context: {
        persona_description: "Knight",
        character_description: "",
        scenario: "Castle",
        character_personality: nil,
      }
    )

    values = input.context_values
    assert_equal 2, values.size
    assert_includes values, "Knight"
    assert_includes values, "Castle"
  end

  def test_force_activate
    input = build_input(forced_activations: ["entry_1", "entry_2"])

    assert input.force_activate?("entry_1")
    assert input.force_activate?("entry_2")
    refute input.force_activate?("entry_3")
  end

  def test_entry_triggered_with_matching_trigger
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: { "triggers" => ["normal", "continue"] },
    )

    input_normal = build_input(trigger: :normal)
    assert input_normal.entry_triggered?(entry)

    input_continue = build_input(trigger: :continue)
    assert input_continue.entry_triggered?(entry)

    input_impersonate = build_input(trigger: :impersonate)
    refute input_impersonate.entry_triggered?(entry)
  end

  def test_entry_triggered_with_no_triggers
    entry = TavernKit::Lore::Entry.new(keys: ["k"], content: "c")

    input = build_input(trigger: :impersonate)
    assert input.entry_triggered?(entry)
  end

  def test_entry_matches_character_with_name_filter
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: { "character_filter_names" => ["Alice", "Bob"] },
    )

    input_alice = build_input(character_name: "Alice")
    assert input_alice.entry_matches_character?(entry)

    input_charlie = build_input(character_name: "Charlie")
    refute input_charlie.entry_matches_character?(entry)
  end

  def test_entry_matches_character_with_tag_filter
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: { "character_filter_tags" => ["fantasy"] },
    )

    input_match = build_input(character_tags: ["fantasy", "female"])
    assert input_match.entry_matches_character?(entry)

    input_no_match = build_input(character_tags: ["scifi"])
    refute input_no_match.entry_matches_character?(entry)
  end

  def test_sticky_active
    input = build_input(
      turn_count: 5,
      timed_state: {
        "entry_1" => { sticky: { end_turn: 7 } },
        "entry_2" => { sticky: { end_turn: 4 } },
      }
    )

    assert input.sticky_active?("entry_1")
    refute input.sticky_active?("entry_2")
    refute input.sticky_active?("entry_3")
  end

  def test_cooldown_active
    input = build_input(
      turn_count: 5,
      timed_state: {
        "entry_1" => { cooldown: { end_turn: 10 } },
        "entry_2" => { cooldown: { end_turn: 5 } },
      }
    )

    assert input.cooldown_active?("entry_1")
    refute input.cooldown_active?("entry_2")
    refute input.cooldown_active?("entry_3")
  end

  def test_delay_active
    input = build_input(
      turn_count: 5,
      timed_state: {
        "entry_1" => { delay: { start_turn: 3, duration: 5 } }, # ends at 8
        "entry_2" => { delay: { start_turn: 2, duration: 2 } }, # ends at 4
      }
    )

    assert input.delay_active?("entry_1")
    refute input.delay_active?("entry_2")
    refute input.delay_active?("entry_3")
  end

  def test_arrays_frozen
    input = build_input(
      scan_injects: ["inject1"],
      character_tags: ["tag1"],
      forced_activations: ["entry_1"]
    )

    assert input.scan_injects.frozen?
    assert input.character_tags.frozen?
    assert input.forced_activations.frozen?
  end

  def test_timed_state_frozen
    state = { "entry_1" => { sticky: { end_turn: 10 } } }
    input = build_input(timed_state: state)
    refute input.timed_state.frozen?
    assert_same state, input.timed_state
  end

  private

  def build_input(
    messages: [],
    books: [],
    budget: 2000,
    **kwargs
  )
    TavernKit::SillyTavern::Lore::ScanInput.new(
      messages: messages,
      books: books,
      budget: budget,
      **kwargs
    )
  end
end
