# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Lore::WorldInfoImporterTest < Minitest::Test
  def test_loads_basic_world_info_entries
    raw = TavernKitTest::Fixtures.json("silly_tavern", "world_info", "basic_entries.json")
    book = TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(raw)

    assert_kind_of TavernKit::Lore::Book, book
    assert_equal 3, book.entry_count

    entry0 = book.entries.first
    assert_kind_of TavernKit::Lore::Entry, entry0
    assert_equal ["Alice", "protagonist"], entry0.keys
    assert_equal "Alice is the main protagonist of the story.", entry0.content
    assert entry0.enabled?
    assert_equal 100, entry0.insertion_order
    refute entry0.constant?
    assert_equal "Main character entry", entry0.comment
    assert_equal "0", entry0.id
    assert_equal "before_char_defs", entry0.position
    assert entry0.extensions.key?("use_probability")

    entry2 = book.entries.last
    assert entry2.constant?
    assert_equal "after_char_defs", entry2.position
  end

  def test_loads_complete_world_info_book
    raw = TavernKitTest::Fixtures.json("silly_tavern", "world_info", "complete_book.json")
    book = TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(raw)

    assert_equal "Test Fantasy Lorebook", book.name
    assert_equal "A lorebook for testing TavernKit's ST compatibility", book.description
    assert_equal 4, book.scan_depth
    assert_equal 2048, book.token_budget
    assert_equal true, book.recursive_scanning?
    assert_equal raw.fetch("entries").size, book.entry_count

    entry0 = book.entries.first
    assert_equal "0", entry0.id
    assert_equal true, entry0.extensions["match_character_description"]
    assert_equal true, entry0.extensions["match_scenario"]

    entry1 = book.entries[1]
    assert_equal ["normal", "continue"], entry1.extensions["triggers"]
    assert_equal ["fantasy"], entry1.extensions["character_filter_tags"]
  end

  def test_normalizes_st_v1150_fields
    raw = TavernKitTest::Fixtures.json("silly_tavern", "world_info", "st_v1150_fields.json")
    book = TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(raw)

    entry0 = book.entries.find { |e| e.id == "0" }
    assert_equal true, entry0.extensions["match_persona_description"]

    entry4 = book.entries.find { |e| e.id == "4" }
    assert_equal ["Bob"], entry4.extensions["character_filter_names"]
    assert_equal true, entry4.extensions["character_filter_exclude"]

    entry6 = book.entries.find { |e| e.id == "6" }
    assert_equal ["continue", "impersonate"], entry6.extensions["triggers"]

    entry7 = book.entries.find { |e| e.id == "7" }
    assert_equal false, entry7.extensions["use_probability"]
  end

  def test_skips_invalid_entries_by_default
    raw = {
      "entries" => {
        "0" => { "content" => "missing keys" },
        "1" => "not a hash",
      },
    }

    book = TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(raw)
    assert_equal 0, book.entry_count
  end

  def test_raises_in_strict_mode_for_invalid_entries
    raw = { "entries" => { "0" => { "content" => "missing keys" } } }

    assert_raises(TavernKit::SillyTavern::LoreParseError) do
      TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(raw, strict: true)
    end
  end
end
