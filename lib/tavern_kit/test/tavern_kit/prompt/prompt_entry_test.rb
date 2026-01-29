# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::PromptEntryTest < Minitest::Test
  def test_basic_initialization
    entry = TavernKit::Prompt::PromptEntry.new(id: "test_001")
    assert_equal "test_001", entry.id
    assert_equal "test_001", entry.name
    assert entry.enabled?
    refute entry.pinned?
    assert_equal :system, entry.role
    assert_equal :relative, entry.position
    assert entry.relative?
    refute entry.in_chat?
    assert_equal 4, entry.depth
    assert_equal 100, entry.order
    assert_nil entry.content
    assert_empty entry.triggers
    refute entry.forbid_overrides
  end

  def test_initialization_with_all_attributes
    entry = TavernKit::Prompt::PromptEntry.new(
      id: "custom_001",
      name: "Custom Prompt",
      enabled: false,
      pinned: true,
      role: :user,
      position: :in_chat,
      depth: 2,
      order: 50,
      content: "Hello world",
      triggers: [:normal, :continue],
      forbid_overrides: true,
      conditions: { turns: { min: 1 } }
    )

    assert_equal "custom_001", entry.id
    assert_equal "Custom Prompt", entry.name
    refute entry.enabled?
    assert entry.pinned?
    assert_equal :user, entry.role
    assert_equal :in_chat, entry.position
    assert entry.in_chat?
    refute entry.relative?
    assert_equal 2, entry.depth
    assert_equal 50, entry.order
    assert_equal "Hello world", entry.content
    assert_includes entry.triggers, :normal
    assert_includes entry.triggers, :continue
    assert entry.forbid_overrides
  end

  def test_coerces_id_and_name_to_string
    entry = TavernKit::Prompt::PromptEntry.new(id: :symbol_id, name: :symbol_name)
    assert_equal "symbol_id", entry.id
    assert_equal "symbol_name", entry.name
  end

  def test_name_defaults_to_id
    entry = TavernKit::Prompt::PromptEntry.new(id: "my_id")
    assert_equal "my_id", entry.name
  end

  def test_to_h_serialization
    entry = TavernKit::Prompt::PromptEntry.new(
      id: "test",
      name: "Test",
      enabled: true,
      pinned: false,
      role: :system,
      position: :relative,
      depth: 4,
      order: 100,
      content: "Test content"
    )

    h = entry.to_h
    assert_equal "test", h[:id]
    assert_equal "Test", h[:name]
    assert_equal true, h[:enabled]
    assert_equal false, h[:pinned]
    assert_equal :system, h[:role]
    assert_equal :relative, h[:position]
    assert_equal 4, h[:depth]
    assert_equal 100, h[:order]
    assert_equal "Test content", h[:content]
  end

  def test_from_hash_basic
    hash = { id: "entry_1", name: "Entry One", content: "Hello" }
    entry = TavernKit::Prompt::PromptEntry.from_hash(hash)

    assert_equal "entry_1", entry.id
    assert_equal "Entry One", entry.name
    assert_equal "Hello", entry.content
  end

  def test_from_hash_with_string_keys
    hash = { "id" => "entry_2", "name" => "Entry Two", "enabled" => false }
    entry = TavernKit::Prompt::PromptEntry.from_hash(hash)

    assert_equal "entry_2", entry.id
    assert_equal "Entry Two", entry.name
    refute entry.enabled?
  end

  def test_from_hash_with_key_fallback
    hash = { key: "fallback_id" }
    entry = TavernKit::Prompt::PromptEntry.from_hash(hash)

    assert_equal "fallback_id", entry.id
  end

  def test_from_hash_returns_nil_without_id
    hash = { name: "No ID" }
    entry = TavernKit::Prompt::PromptEntry.from_hash(hash)

    assert_nil entry
  end

  def test_from_hash_coerces_position
    hash = { id: "test", position: "in_chat" }
    entry = TavernKit::Prompt::PromptEntry.from_hash(hash)

    assert_equal :in_chat, entry.position
    assert entry.in_chat?
  end

  def test_from_hash_defaults_position_to_relative
    hash = { id: "test", position: "anything_else" }
    entry = TavernKit::Prompt::PromptEntry.from_hash(hash)

    assert_equal :relative, entry.position
    assert entry.relative?
  end

  # --- Trigger Tests ---

  def test_triggered_by_returns_true_when_no_triggers
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", triggers: [])
    assert entry.triggered_by?(:normal)
    assert entry.triggered_by?(:continue)
    assert entry.triggered_by?(:impersonate)
  end

  def test_triggered_by_returns_true_when_match
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", triggers: [:normal, :continue])
    assert entry.triggered_by?(:normal)
    assert entry.triggered_by?(:continue)
    refute entry.triggered_by?(:impersonate)
  end

  def test_triggered_by_coerces_input
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", triggers: [:normal])
    assert entry.triggered_by?("normal")
    assert entry.triggered_by?(0)
  end

  # --- Condition Tests ---

  def test_active_for_returns_true_when_no_conditions
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: nil)
    assert entry.active_for?({})
    assert entry.active_for?({ turn_count: 5 })
  end

  def test_active_for_returns_true_when_empty_conditions
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: {})
    assert entry.active_for?({})
  end

  def test_active_for_returns_false_for_non_hash_context
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { turns: { min: 1 } })
    refute entry.active_for?(nil)
    refute entry.active_for?("invalid")
  end

  # --- Turns Conditions ---

  def test_turns_min_condition
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { turns: { min: 5 } })
    refute entry.active_for?({ turn_count: 3 })
    assert entry.active_for?({ turn_count: 5 })
    assert entry.active_for?({ turn_count: 10 })
  end

  def test_turns_max_condition
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { turns: { max: 10 } })
    assert entry.active_for?({ turn_count: 5 })
    assert entry.active_for?({ turn_count: 10 })
    refute entry.active_for?({ turn_count: 11 })
  end

  def test_turns_equals_condition
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { turns: { equals: 5 } })
    refute entry.active_for?({ turn_count: 4 })
    assert entry.active_for?({ turn_count: 5 })
    refute entry.active_for?({ turn_count: 6 })
  end

  def test_turns_every_condition
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { turns: { every: 3 } })
    assert entry.active_for?({ turn_count: 0 })
    refute entry.active_for?({ turn_count: 1 })
    refute entry.active_for?({ turn_count: 2 })
    assert entry.active_for?({ turn_count: 3 })
    refute entry.active_for?({ turn_count: 4 })
    assert entry.active_for?({ turn_count: 6 })
  end

  def test_turns_every_zero_returns_false
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { turns: { every: 0 } })
    refute entry.active_for?({ turn_count: 5 })
  end

  def test_turns_shorthand_integer
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { turns: 5 })
    refute entry.active_for?({ turn_count: 4 })
    assert entry.active_for?({ turn_count: 5 })
    refute entry.active_for?({ turn_count: 6 })
  end

  # --- Chat Conditions ---

  def test_chat_any_condition
    entry = TavernKit::Prompt::PromptEntry.new(
      id: "test",
      conditions: { chat: { any: ["hello", "world"] } }
    )

    assert entry.active_for?({ chat_scan_messages: ["hello there"] })
    assert entry.active_for?({ chat_scan_messages: ["the world"] })
    refute entry.active_for?({ chat_scan_messages: ["goodbye"] })
  end

  def test_chat_all_condition
    entry = TavernKit::Prompt::PromptEntry.new(
      id: "test",
      conditions: { chat: { all: ["hello", "world"] } }
    )

    refute entry.active_for?({ chat_scan_messages: ["hello there"] })
    refute entry.active_for?({ chat_scan_messages: ["the world"] })
    assert entry.active_for?({ chat_scan_messages: ["hello world"] })
  end

  def test_chat_depth_limits_messages
    entry = TavernKit::Prompt::PromptEntry.new(
      id: "test",
      conditions: { chat: { any: ["target"], depth: 2 } }
    )

    # Only first 2 messages scanned
    assert entry.active_for?({ chat_scan_messages: ["target", "other", "more"] })
    refute entry.active_for?({ chat_scan_messages: ["other", "more", "target"] })
  end

  def test_chat_shorthand_string
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { chat: "keyword" })
    assert entry.active_for?({ chat_scan_messages: ["contains keyword here"] })
    refute entry.active_for?({ chat_scan_messages: ["no match"] })
  end

  def test_chat_shorthand_array
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { chat: ["foo", "bar"] })
    assert entry.active_for?({ chat_scan_messages: ["foo is here"] })
    assert entry.active_for?({ chat_scan_messages: ["bar is here"] })
    refute entry.active_for?({ chat_scan_messages: ["baz is here"] })
  end

  # --- Character Conditions ---

  def test_character_name_condition
    character = Struct.new(:data).new(Struct.new(:name).new("Alice"))
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { character: { name: "Alice" } })

    assert entry.active_for?({ character: character })
    refute entry.active_for?({ character: Struct.new(:data).new(Struct.new(:name).new("Bob")) })
  end

  def test_character_shorthand_string
    character = Struct.new(:data).new(Struct.new(:name).new("Alice"))
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { character: "Alice" })

    assert entry.active_for?({ character: character })
  end

  def test_character_tags_any_condition
    character = Struct.new(:data).new(Struct.new(:name, :tags).new("Alice", ["fantasy", "female"]))
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { character: { tags_any: ["fantasy", "scifi"] } })

    assert entry.active_for?({ character: character })

    char_no_match = Struct.new(:data).new(Struct.new(:name, :tags).new("Bob", ["modern"]))
    refute entry.active_for?({ character: char_no_match })
  end

  def test_character_tags_all_condition
    character = Struct.new(:data).new(Struct.new(:name, :tags).new("Alice", ["fantasy", "female"]))
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { character: { tags_all: ["fantasy", "female"] } })

    assert entry.active_for?({ character: character })

    char_partial = Struct.new(:data).new(Struct.new(:name, :tags).new("Bob", ["fantasy"]))
    refute entry.active_for?({ character: char_partial })
  end

  def test_character_returns_false_without_character
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { character: { name: "Alice" } })
    refute entry.active_for?({ character: nil })
    refute entry.active_for?({})
  end

  # --- User Conditions ---

  def test_user_name_condition
    user = Struct.new(:name).new("Bob")
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { user: { name: "Bob" } })

    assert entry.active_for?({ user: user })
    refute entry.active_for?({ user: Struct.new(:name).new("Alice") })
  end

  def test_user_shorthand_string
    user = Struct.new(:name).new("Bob")
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { user: "Bob" })

    assert entry.active_for?({ user: user })
  end

  def test_user_persona_condition
    user = Struct.new(:name, :persona_text).new("Bob", "I am a brave knight")
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { user: { persona: "knight" } })

    assert entry.active_for?({ user: user })

    user_no_match = Struct.new(:name, :persona_text).new("Alice", "I am a wizard")
    refute entry.active_for?({ user: user_no_match })
  end

  def test_user_returns_false_without_user
    entry = TavernKit::Prompt::PromptEntry.new(id: "test", conditions: { user: { name: "Bob" } })
    refute entry.active_for?({ user: nil })
    refute entry.active_for?({})
  end

  # --- Composite Conditions ---

  def test_all_composite_condition
    entry = TavernKit::Prompt::PromptEntry.new(
      id: "test",
      conditions: {
        all: [
          { turns: { min: 2 } },
          { turns: { max: 10 } },
        ],
      }
    )

    refute entry.active_for?({ turn_count: 1 })
    assert entry.active_for?({ turn_count: 5 })
    refute entry.active_for?({ turn_count: 11 })
  end

  def test_any_composite_condition
    character_alice = Struct.new(:data).new(Struct.new(:name).new("Alice"))
    character_bob = Struct.new(:data).new(Struct.new(:name).new("Bob"))
    character_charlie = Struct.new(:data).new(Struct.new(:name).new("Charlie"))

    entry = TavernKit::Prompt::PromptEntry.new(
      id: "test",
      conditions: {
        any: [
          { character: "Alice" },
          { character: "Bob" },
        ],
      }
    )

    assert entry.active_for?({ character: character_alice })
    assert entry.active_for?({ character: character_bob })
    refute entry.active_for?({ character: character_charlie })
  end

  def test_multiple_condition_types_combined
    character = Struct.new(:data).new(Struct.new(:name).new("Alice"))
    user = Struct.new(:name).new("Bob")

    entry = TavernKit::Prompt::PromptEntry.new(
      id: "test",
      conditions: {
        character: "Alice",
        user: "Bob",
        turns: { min: 1 },
      }
    )

    assert entry.active_for?({ character: character, user: user, turn_count: 5 })
    refute entry.active_for?({ character: character, user: user, turn_count: 0 })
    refute entry.active_for?({ character: character, user: Struct.new(:name).new("Charlie"), turn_count: 5 })
  end
end
