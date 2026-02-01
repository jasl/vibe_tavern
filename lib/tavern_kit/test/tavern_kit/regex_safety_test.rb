# frozen_string_literal: true

require "test_helper"

class TavernKit::RegexSafetyTest < Minitest::Test
  def test_compile_returns_regexp_for_valid_pattern
    re = TavernKit::RegexSafety.compile("cat")
    assert_kind_of Regexp, re
    assert re.match?("a cat b")
  end

  def test_compile_returns_nil_for_oversized_pattern
    too_big = "a" * (TavernKit::RegexSafety::DEFAULT_MAX_PATTERN_BYTES + 1)
    assert_nil TavernKit::RegexSafety.compile(too_big)
  end

  def test_match_returns_false_for_oversized_input
    re = /a/
    too_big = "a" * (TavernKit::RegexSafety::DEFAULT_MAX_INPUT_BYTES + 1)

    assert_equal false, TavernKit::RegexSafety.match?(re, too_big)
    assert_nil TavernKit::RegexSafety.match(re, too_big)
  end
end
