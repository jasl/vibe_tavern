# frozen_string_literal: true

require "test_helper"

class TavernKit::JsRegexCacheTest < Minitest::Test
  def test_fetch_returns_nil_for_non_literal
    cache = TavernKit::JsRegexCache.new(max_size: 10)
    assert_nil cache.fetch("cat")
  end

  def test_fetch_caches_converted_regex
    cache = TavernKit::JsRegexCache.new(max_size: 10)

    r1 = cache.fetch("/cat/i")
    r2 = cache.fetch("/cat/i")

    refute_nil r1
    assert_same r1, r2
  end

  def test_cache_is_bounded
    cache = TavernKit::JsRegexCache.new(max_size: 1)

    r1 = cache.fetch("/cat/i")
    cache.fetch("/dog/i")

    r1_again = cache.fetch("/cat/i")
    refute_same r1, r1_again
  end
end
