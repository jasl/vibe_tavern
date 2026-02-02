# frozen_string_literal: true

require "test_helper"

class TavernKit::Lore::EntryTest < Minitest::Test
  def test_from_h_and_to_h
    entry = TavernKit::Lore::Entry.from_h(
      "keys" => ["a", "b"],
      "content" => "hello",
      "use_regex" => true,
      "extensions" => { "st" => { "sticky" => true } },
    )

    assert entry.enabled?
    assert entry.regex?
    assert_equal ["a", "b"], entry.keys
    assert_equal "hello", entry.content
    assert_equal({ "st" => { "sticky" => true } }, entry.extensions)

    h = entry.to_h
    assert_equal ["a", "b"], h["keys"]
    assert_equal "hello", h["content"]
    assert_equal true, h["use_regex"]
    assert_equal({ "st" => { "sticky" => true } }, h["extensions"])
  end

  def test_selective_requires_secondary_keys
    entry = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", selective: true, secondary_keys: ["s"])
    assert entry.selective?

    entry2 = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", selective: true, secondary_keys: [])
    refute entry2.selective?
  end
end
