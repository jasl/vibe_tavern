# frozen_string_literal: true

require "test_helper"

class LruCacheTest < Minitest::Test
  def test_set_get_and_eviction
    c = TavernKit::LRUCache.new(max_size: 2)

    c.set("a", 1)
    c.set("b", 2)
    assert_equal 2, c.size

    # Touch "a" so it becomes most-recent.
    assert_equal 1, c.get("a")

    # Insert "c" => evicts "b".
    c.set("c", 3)
    assert_equal 2, c.size
    assert_nil c.get("b")
    assert_equal 1, c.get("a")
    assert_equal 3, c.get("c")
  end

  def test_fetch_caches_computed_values
    c = TavernKit::LRUCache.new(max_size: 1)
    seen = 0

    v1 = c.fetch(:k) { seen += 1; "v" }
    v2 = c.fetch(:k) { seen += 1; "v2" }

    assert_equal "v", v1
    assert_equal "v", v2
    assert_equal 1, seen
  end

  def test_fetch_raises_without_block
    c = TavernKit::LRUCache.new(max_size: 1)
    assert_raises(KeyError) { c.fetch(:missing) }
  end

  def test_fetch_can_cache_nil
    c = TavernKit::LRUCache.new(max_size: 1)
    seen = 0

    v1 = c.fetch(:k) { seen += 1; nil }
    v2 = c.fetch(:k) { seen += 1; "x" }

    assert_nil v1
    assert_nil v2
    assert_equal 1, seen
  end
end
