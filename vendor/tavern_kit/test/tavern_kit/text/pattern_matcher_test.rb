# frozen_string_literal: true

require "test_helper"

class TavernKit::Text::PatternMatcherTest < Minitest::Test
  def test_match_plain_substring_case_insensitive
    assert TavernKit::Text::PatternMatcher.match?(
      "cat",
      "A Cat appears.",
      case_sensitive: false,
      match_whole_words: false,
    )
  end

  def test_match_plain_whole_word
    refute TavernKit::Text::PatternMatcher.match?(
      "cat",
      "concatenate",
      case_sensitive: false,
      match_whole_words: true,
    )

    assert TavernKit::Text::PatternMatcher.match?(
      "cat",
      "the cat.",
      case_sensitive: false,
      match_whole_words: true,
    )
  end

  def test_match_js_regex_respects_case_sensitive_flag
    assert TavernKit::Text::PatternMatcher.match?(
      "/cat/",
      "A Cat appears.",
      case_sensitive: false,
      match_whole_words: false,
    )

    refute TavernKit::Text::PatternMatcher.match?(
      "/cat/",
      "A Cat appears.",
      case_sensitive: true,
      match_whole_words: false,
    )

    assert TavernKit::Text::PatternMatcher.match?(
      "/cat/i",
      "A Cat appears.",
      case_sensitive: true,
      match_whole_words: false,
    )
  end
end
