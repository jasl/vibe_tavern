# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Lore::EntryExtensionsTest < Minitest::Test
  def test_defaults
    entry = TavernKit::Lore::Entry.new(keys: ["k"], content: "c")
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    refute ext.match_persona_description?
    refute ext.match_character_description?
    refute ext.match_character_personality?
    refute ext.match_character_depth_prompt?
    refute ext.match_scenario?
    refute ext.match_creator_notes?
    refute ext.match_non_chat_data?

    refute ext.has_character_filter?
    assert_equal [], ext.character_filter_names
    assert_equal [], ext.character_filter_tags
    refute ext.character_filter_exclude?
    assert ext.matches_character?(character_name: "Alice", character_tags: ["fantasy"])

    refute ext.has_triggers?
    assert_equal [], ext.triggers
    assert ext.triggered_by?(:normal)
    assert ext.triggered_by?(:continue)

    assert ext.use_probability?
    assert_nil ext.outlet_name
  end

  def test_reads_camel_case_and_snake_case_keys_from_extensions
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: {
        "matchPersonaDescription" => true,
        "characterFilterNames" => ["Alice", "Bob"],
        "characterFilterTags" => ["fantasy"],
        "characterFilterExclude" => false,
        "triggers" => ["normal", "continue"],
        "useProbability" => false,
        "outletName" => "outlet1",
      },
    )
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    assert ext.match_persona_description?
    refute ext.use_probability?
    assert_equal "outlet1", ext.outlet_name
    assert_equal ["Alice", "Bob"], ext.character_filter_names
    assert_equal ["fantasy"], ext.character_filter_tags
    assert_equal [:normal, :continue], ext.triggers
  end

  def test_snake_case_takes_precedence_over_camel_case
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: {
        "matchPersonaDescription" => true,
        "match_persona_description" => false,
      },
    )
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    refute ext.match_persona_description?
  end

  def test_triggered_by
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: { "triggers" => ["normal", "continue"] },
    )
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    assert ext.triggered_by?(:normal)
    assert ext.triggered_by?("continue")
    refute ext.triggered_by?(:impersonate)
  end

  def test_matches_character_by_name_or_tags
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: {
        "character_filter_names" => ["Alice"],
        "character_filter_tags" => ["fantasy"],
      },
    )
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    assert ext.matches_character?(character_name: "Alice")
    assert ext.matches_character?(character_tags: ["fantasy", "other"])
    refute ext.matches_character?(character_name: "Bob", character_tags: ["scifi"])
  end

  def test_matches_character_with_exclude_inverts_match
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: {
        "character_filter_names" => ["Alice"],
        "character_filter_exclude" => true,
      },
    )
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    refute ext.matches_character?(character_name: "Alice")
    assert ext.matches_character?(character_name: "Bob")
  end

  def test_match_non_chat_data_predicate
    entry = TavernKit::Lore::Entry.new(
      keys: ["k"],
      content: "c",
      extensions: { "match_scenario" => true },
    )
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    assert ext.match_non_chat_data?
  end

  def test_outlet_name_presence
    entry_blank = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "outletName" => "" })
    ext_blank = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_blank)
    assert_nil ext_blank.outlet_name

    entry_value = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "outletName" => "wiBefore" })
    ext_value = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_value)
    assert_equal "wiBefore", ext_value.outlet_name
  end

  def test_use_probability_default_and_override
    entry_default = TavernKit::Lore::Entry.new(keys: ["k"], content: "c")
    ext_default = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_default)
    assert ext_default.use_probability?

    entry_false = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "useProbability" => false })
    ext_false = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_false)
    refute ext_false.use_probability?
  end
end
