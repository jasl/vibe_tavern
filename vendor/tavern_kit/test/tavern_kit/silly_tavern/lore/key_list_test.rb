# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Lore::KeyListTest < Minitest::Test
  def test_parse_nil
    assert_equal [], TavernKit::SillyTavern::Lore::KeyList.parse(nil)
  end

  def test_parse_array
    assert_equal ["a", "b"], TavernKit::SillyTavern::Lore::KeyList.parse(["a", " b "])
  end

  def test_parse_string_splits_on_commas
    assert_equal ["a", "b", "c"], TavernKit::SillyTavern::Lore::KeyList.parse("a, b, c")
  end

  def test_parse_string_allows_commas_inside_js_regex_literal
    tokens = TavernKit::SillyTavern::Lore::KeyList.parse("/foo,bar/i, baz")
    assert_equal ["/foo,bar/i", "baz"], tokens
  end

  def test_parse_string_handles_escaped_slash_inside_regex_literal
    tokens = TavernKit::SillyTavern::Lore::KeyList.parse("/foo\\/bar/i, baz")
    assert_equal ["/foo\\/bar/i", "baz"], tokens
  end
end
