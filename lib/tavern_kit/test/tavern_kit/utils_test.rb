# frozen_string_literal: true

require "test_helper"

class TavernKit::UtilsTest < Minitest::Test
  def test_deep_symbolize_keys
    input = { "name" => "Test", "nested" => { "key" => "value" } }
    result = TavernKit::Utils.deep_symbolize_keys(input)
    assert_equal({ name: "Test", nested: { key: "value" } }, result)
  end

  def test_deep_symbolize_keys_with_array
    input = [{ "a" => 1 }, { "b" => 2 }]
    result = TavernKit::Utils.deep_symbolize_keys(input)
    assert_equal([{ a: 1 }, { b: 2 }], result)
  end

  def test_deep_stringify_keys
    input = { name: "Test", nested: { key: "value" } }
    result = TavernKit::Utils.deep_stringify_keys(input)
    assert_equal({ "name" => "Test", "nested" => { "key" => "value" } }, result)
  end

  def test_presence_with_value
    assert_equal "hello", TavernKit::Utils.presence("hello")
  end

  def test_presence_with_blank
    assert_nil TavernKit::Utils.presence("")
    assert_nil TavernKit::Utils.presence("  ")
  end

  def test_presence_with_nil
    assert_nil TavernKit::Utils.presence(nil)
  end

  def test_string_format
    assert_equal "Hello, World!", TavernKit::Utils.string_format("Hello, {0}!", "World")
    assert_equal "a and b", TavernKit::Utils.string_format("{0} and {1}", "a", "b")
    assert_equal "no {2} match", TavernKit::Utils.string_format("no {2} match", "a", "b")
  end

  def test_underscore
    assert_equal "match_persona_description", TavernKit::Utils.underscore("matchPersonaDescription")
    assert_equal "use_probability", TavernKit::Utils.underscore("use_probability")
  end

  def test_camelize_lower
    assert_equal "useProbability", TavernKit::Utils.camelize_lower("use_probability")
    assert_equal "useProbability", TavernKit::Utils.camelize_lower("useProbability")
  end

  def test_hash_accessor_basic
    h = TavernKit::Utils::HashAccessor.wrap({ "name" => "Test", key: "value" })
    assert_equal "Test", h[:name]
    assert_equal "value", h[:key]
  end

  def test_hash_accessor_fetch_default
    h = TavernKit::Utils::HashAccessor.wrap({})
    assert_nil h[:missing]
    assert_equal "default", h.fetch(:missing, default: "default")
  end

  def test_hash_accessor_dig
    h = TavernKit::Utils::HashAccessor.wrap({ "extensions" => { "world" => "Narnia" } })
    assert_equal "Narnia", h.dig(:extensions, :world)
  end

  def test_hash_accessor_supports_camel_case_keys
    h = TavernKit::Utils::HashAccessor.wrap(
      {
        "useProbability" => true,
        "extensions" => { "matchPersonaDescription" => true },
      },
    )

    assert h.bool(:use_probability)
    assert h.bool(:match_persona_description, ext_key: :match_persona_description)
  end

  def test_hash_accessor_prefers_snake_case_when_both_present
    h = TavernKit::Utils::HashAccessor.wrap(
      {
        "use_probability" => false,
        "useProbability" => true,
      },
    )

    refute h.bool(:use_probability, default: true)
  end

  def test_hash_accessor_bool
    h = TavernKit::Utils::HashAccessor.wrap({ "enabled" => true, "disabled" => false })
    assert h.bool(:enabled)
    refute h.bool(:disabled)
    refute h.bool(:missing)
  end

  def test_hash_accessor_int
    h = TavernKit::Utils::HashAccessor.wrap({ "count" => 5 })
    assert_equal 5, h.int(:count)
    assert_equal 0, h.int(:missing)
    assert_equal 42, h.int(:missing, default: 42)
  end
end
