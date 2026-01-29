# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::InstructTest < Minitest::Test
  def test_with_returns_new_instance
    instruct = TavernKit::SillyTavern::Instruct.new(enabled: true, preset: "A")
    other = instruct.with(preset: "B")

    refute_same instruct, other
    assert_equal "A", instruct.preset
    assert_equal "B", other.preset
  end

  def test_names_behavior_coerce
    nb = TavernKit::SillyTavern::Instruct::NamesBehavior

    assert_equal :none, nb.coerce(0)
    assert_equal :force, nb.coerce(1)
    assert_equal :always, nb.coerce(2)
    assert_equal :force, nb.coerce(nil)
  end

  def test_stopping_sequences_splits_multiline_and_applies_wrap_and_macro
    instruct = TavernKit::SillyTavern::Instruct.new(
      enabled: true,
      stop_sequence: "STOP\nSTOP2",
      input_sequence: "IN {{name}}",
      output_sequence: "OUT {{name}}",
      system_sequence: "SYS {{name}}",
      wrap: true,
      macro: true,
      sequences_as_stop_strings: true,
    )

    macro_expander = ->(s) { s.gsub("STOP", "S").gsub("IN", "I") }

    stops = instruct.stopping_sequences(user_name: "Bob", char_name: "Alice", macro_expander: macro_expander)

    assert_includes stops, "\nS"
    assert_includes stops, "\nS2"
    assert_includes stops, "\nI Bob"
    assert_includes stops, "\nOUT Alice"
    assert_includes stops, "\nSYS System"
  end

  def test_from_st_json_migrates_separator_sequence_and_names_fields
    instruct = TavernKit::SillyTavern::Instruct.from_st_json(
      {
        "name" => "X",
        "separator_sequence" => "\n\n",
        "names" => true,
      },
    )

    assert_equal "X", instruct.preset
    assert_equal "\n\n", instruct.output_suffix
    assert_equal :always, instruct.names_behavior
  end
end
