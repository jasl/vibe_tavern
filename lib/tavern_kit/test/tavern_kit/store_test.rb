# frozen_string_literal: true

require "test_helper"

class TavernKit::StoreTest < Minitest::Test
  def test_set_get_has_delete
    vars = TavernKit::Store::InMemory.new

    refute vars.has?("foo")
    assert_nil vars.get("foo")

    vars.set("foo", "bar")
    assert vars.has?("foo")
    assert_equal "bar", vars.get("foo")

    assert_equal "bar", vars.delete("foo")
    refute vars.has?("foo")
  end

  def test_scopes_are_independent
    vars = TavernKit::Store::InMemory.new

    vars.set("x", "local")
    vars.set("x", "global", scope: :global)

    assert_equal "local", vars.get("x")
    assert_equal "global", vars.get("x", scope: :global)
  end

  def test_add_numeric_and_string
    vars = TavernKit::Store::InMemory.new

    vars.set("n", 1)
    vars.add("n", 2)
    assert_equal 3, vars.get("n")

    vars.set("s", "a")
    vars.add("s", "b")
    assert_equal "ab", vars.get("s")
  end

  def test_cache_version_increments_on_writes
    vars = TavernKit::Store::InMemory.new

    v0 = vars.cache_version
    vars.set("a", "1")
    assert_operator vars.cache_version, :>, v0

    v1 = vars.cache_version
    vars.get("a")
    assert_equal v1, vars.cache_version

    vars.add("a", "2")
    assert_operator vars.cache_version, :>, v1
  end
end
