# frozen_string_literal: true

require "test_helper"

class TavernKit::Text::JSONPointerTest < Minitest::Test
  def test_escape_and_unescape_round_trip
    original = "a/b~c"
    escaped = TavernKit::Text::JSONPointer.escape(original)
    assert_equal "a~1b~0c", escaped
    assert_equal original, TavernKit::Text::JSONPointer.unescape(escaped)
  end

  def test_tokens_and_from_tokens
    assert_equal [], TavernKit::Text::JSONPointer.tokens("")

    pointer = "/a~1b/m~0n/"
    tokens = TavernKit::Text::JSONPointer.tokens(pointer)
    assert_equal ["a/b", "m~n", ""], tokens

    assert_equal pointer, TavernKit::Text::JSONPointer.from_tokens(tokens)
  end

  def test_valid_predicate
    assert TavernKit::Text::JSONPointer.valid?("/a")
    refute TavernKit::Text::JSONPointer.valid?("a")
  end

  def test_unescape_raises_for_invalid_sequences
    assert_raises(ArgumentError) { TavernKit::Text::JSONPointer.unescape("a~2b") }
    assert_raises(ArgumentError) { TavernKit::Text::JSONPointer.unescape("a~") }
  end
end
