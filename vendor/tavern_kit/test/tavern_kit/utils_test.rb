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

  def test_normalize_symbol_keyed_hash
    assert_equal({}, TavernKit::Utils.normalize_symbol_keyed_hash(nil, path: "cfg"))

    input = { a: { b: 1 } }
    normalized = TavernKit::Utils.normalize_symbol_keyed_hash(input, path: "cfg")
    assert_same input, normalized
  end

  def test_normalize_symbol_keyed_hash_rejects_non_hash
    error =
      assert_raises(ArgumentError) do
        TavernKit::Utils.normalize_symbol_keyed_hash("nope", path: "cfg")
      end
    assert_includes error.message, "cfg must be a Hash"
  end

  def test_assert_deep_symbol_keys_bubbles_path
    error =
      assert_raises(ArgumentError) do
        TavernKit::Utils.assert_deep_symbol_keys!({ a: { "b" => 1 } }, path: "cfg")
      end
    assert_includes error.message, "cfg.a keys must be Symbols"
  end

  def test_assert_symbol_keys_rejects_non_hash
    error =
      assert_raises(ArgumentError) do
        TavernKit::Utils.assert_symbol_keys!("nope", path: "cfg")
      end
    assert_includes error.message, "cfg must be a Hash"
  end

  def test_assert_symbol_keys_rejects_non_symbol_keys
    error =
      assert_raises(ArgumentError) do
        TavernKit::Utils.assert_symbol_keys!({ "a" => 1 }, path: "cfg")
      end
    assert_includes error.message, "cfg keys must be Symbols"
  end

  def test_normalize_request_overrides
    assert_equal({}, TavernKit::Utils.normalize_request_overrides(nil))

    input = { a: { b: 1 } }
    normalized = TavernKit::Utils.normalize_request_overrides(input)
    assert_same input, normalized

    error =
      assert_raises(ArgumentError) do
        TavernKit::Utils.normalize_request_overrides({ "a" => 1 })
      end
    assert_includes error.message, "request_overrides keys must be Symbols"
  end

  def test_normalize_string_list
    assert_nil TavernKit::Utils.normalize_string_list(nil)
    assert_nil TavernKit::Utils.normalize_string_list([])
    assert_nil TavernKit::Utils.normalize_string_list([" ", ""])

    assert_equal ["a"], TavernKit::Utils.normalize_string_list("a")
    assert_equal ["a"], TavernKit::Utils.normalize_string_list(["a"])
    assert_equal ["a", "b"], TavernKit::Utils.normalize_string_list(["a", "  b  "])
  end

  def test_explicit_empty_string_list
    assert TavernKit::Utils.explicit_empty_string_list?("")
    assert TavernKit::Utils.explicit_empty_string_list?(" , ")
    assert TavernKit::Utils.explicit_empty_string_list?([])
    assert TavernKit::Utils.explicit_empty_string_list?([" ", ""])
    refute TavernKit::Utils.explicit_empty_string_list?(nil)
    refute TavernKit::Utils.explicit_empty_string_list?("a")
  end

  def test_merge_string_list
    assert_nil TavernKit::Utils.merge_string_list(["a"], nil)
    assert_equal [], TavernKit::Utils.merge_string_list(["a"], "")
    assert_equal ["a"], TavernKit::Utils.merge_string_list(nil, ["a"])
    assert_equal ["a", "b"], TavernKit::Utils.merge_string_list(["a"], ["b", "a"])
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

  def test_hash_accessor_fetch_preserves_false
    h = TavernKit::Utils::HashAccessor.wrap({ "enabled" => false })
    assert_equal false, h.fetch(:enabled, default: true)
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

  def test_hash_accessor_bool_parses_false_strings_with_default_true
    h = TavernKit::Utils::HashAccessor.wrap(
      {
        "enabled" => "false",
        "disabled" => "0",
        "other" => "no",
      },
    )

    refute h.bool(:enabled, default: true)
    refute h.bool(:disabled, default: true)
    refute h.bool(:other, default: true)
  end

  def test_hash_accessor_int
    h = TavernKit::Utils::HashAccessor.wrap({ "count" => 5 })
    assert_equal 5, h.int(:count)
    assert_equal 0, h.int(:missing)
    assert_equal 42, h.int(:missing, default: 42)
  end

  def test_hash_accessor_int_treats_booleans_as_missing
    h = TavernKit::Utils::HashAccessor.wrap({ "count" => false, "other" => true })
    assert_equal 0, h.int(:count)
    assert_equal 7, h.int(:count, default: 7)
    assert_equal 0, h.int(:other)
    assert_nil h.positive_int(:count)
    assert_nil h.positive_int(:other)
  end
end
