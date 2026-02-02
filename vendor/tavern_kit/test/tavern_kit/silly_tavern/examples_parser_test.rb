# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::ExamplesParserTest < Minitest::Test
  def test_parse_empty
    assert_equal [], TavernKit::SillyTavern::ExamplesParser.parse("")
    assert_equal [], TavernKit::SillyTavern::ExamplesParser.parse("<START>")
  end

  def test_parse_defaults_to_plain_blocks
    blocks = TavernKit::SillyTavern::ExamplesParser.parse("Hello")
    assert_equal ["Hello\n"], blocks
  end

  def test_parse_openai_uses_start_heading
    blocks = TavernKit::SillyTavern::ExamplesParser.parse("Hello", main_api: "openai")
    assert_equal ["<START>\nHello\n"], blocks
  end

  def test_parse_non_openai_uses_example_separator
    blocks =
      TavernKit::SillyTavern::ExamplesParser.parse(
        "<START>\nA\n<START>\nB",
        main_api: "kobold",
        example_separator: "***",
      )

    assert_equal ["***\nA\n", "***\nB\n"], blocks
  end

  def test_parse_instruct_forces_start_heading
    blocks =
      TavernKit::SillyTavern::ExamplesParser.parse(
        "<START>\nA\n<START>\nB",
        main_api: "kobold",
        is_instruct: true,
        example_separator: "***",
      )

    assert_equal ["<START>\nA\n", "<START>\nB\n"], blocks
  end
end
