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
    assert_equal 100, ext.probability
    assert_nil ext.outlet_name

    assert_equal 4, ext.depth
    assert_equal :system, ext.role

    assert_equal :and_any, ext.selective_logic

    refute ext.ignore_budget?
    refute ext.exclude_recursion?
    refute ext.prevent_recursion?
    refute ext.delay_until_recursion?

    assert_nil ext.scan_depth
    assert_nil ext.match_whole_words

    assert_nil ext.sticky
    assert_nil ext.cooldown
    assert_nil ext.delay

    assert_nil ext.group
    assert_equal [], ext.group_names
    refute ext.group_override?
    assert_equal 100, ext.group_weight
    assert_nil ext.use_group_scoring
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
        "probability" => 42,
        "outletName" => "outlet1",
        "depth" => 2,
        "role" => 2,
        "selectiveLogic" => 3,
        "ignoreBudget" => true,
        "excludeRecursion" => true,
        "preventRecursion" => true,
        "delayUntilRecursion" => true,
        "scanDepth" => 3,
        "matchWholeWords" => true,
        "sticky" => 2,
        "cooldown" => 3,
        "delay" => 4,
        "group" => "a, b",
        "groupOverride" => true,
        "groupWeight" => 123,
        "useGroupScoring" => true,
      },
    )
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)

    assert ext.match_persona_description?
    refute ext.use_probability?
    assert_equal 42, ext.probability
    assert_equal "outlet1", ext.outlet_name
    assert_equal ["Alice", "Bob"], ext.character_filter_names
    assert_equal ["fantasy"], ext.character_filter_tags
    assert_equal [:normal, :continue], ext.triggers

    assert_equal 2, ext.depth
    assert_equal :assistant, ext.role
    assert_equal :and_all, ext.selective_logic
    assert ext.ignore_budget?
    assert ext.exclude_recursion?
    assert ext.prevent_recursion?
    assert ext.delay_until_recursion?
    assert_equal 1, ext.delay_until_recursion_level
    assert_equal 3, ext.scan_depth
    assert_equal true, ext.match_whole_words
    assert_equal 2, ext.sticky
    assert_equal 3, ext.cooldown
    assert_equal 4, ext.delay
    assert_equal "a, b", ext.group
    assert_equal ["a", "b"], ext.group_names
    assert ext.group_override?
    assert_equal 123, ext.group_weight
    assert_equal true, ext.use_group_scoring
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

  def test_selective_logic_defaults_and_coercions
    entry_default = TavernKit::Lore::Entry.new(keys: ["k"], content: "c")
    ext_default = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_default)
    assert_equal :and_any, ext_default.selective_logic

    entry_int = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "selectiveLogic" => 1 })
    ext_int = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_int)
    assert_equal :not_all, ext_int.selective_logic

    entry_str = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "selective_logic" => "2" })
    ext_str = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_str)
    assert_equal :not_any, ext_str.selective_logic

    entry_sym = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "selective_logic" => "and_all" })
    ext_sym = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_sym)
    assert_equal :and_all, ext_sym.selective_logic
  end

  def test_delay_until_recursion_level_coercion
    entry_false = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "delayUntilRecursion" => false })
    ext_false = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_false)
    assert_nil ext_false.delay_until_recursion_level
    refute ext_false.delay_until_recursion?

    entry_true = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "delayUntilRecursion" => true })
    ext_true = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_true)
    assert_equal 1, ext_true.delay_until_recursion_level

    entry_level = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "delay_until_recursion" => 3 })
    ext_level = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry_level)
    assert_equal 3, ext_level.delay_until_recursion_level
  end

  def test_probability_clamped
    entry = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "probability" => 9001 })
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)
    assert_equal 100, ext.probability

    entry2 = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "probability" => -5 })
    ext2 = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry2)
    assert_equal 0, ext2.probability
  end

  def test_group_weight_minimum
    entry = TavernKit::Lore::Entry.new(keys: ["k"], content: "c", extensions: { "groupWeight" => 0 })
    ext = TavernKit::SillyTavern::Lore::EntryExtensions.wrap(entry)
    assert_equal 1, ext.group_weight
  end
end
