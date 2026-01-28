# frozen_string_literal: true

require "test_helper"

class TavernKit::CoerceTest < Minitest::Test
  def test_bool_true_values
    assert TavernKit::Coerce.bool(true, default: false)
    assert TavernKit::Coerce.bool("1", default: false)
    assert TavernKit::Coerce.bool("true", default: false)
    assert TavernKit::Coerce.bool("yes", default: false)
    assert TavernKit::Coerce.bool("TRUE", default: false)
  end

  def test_bool_false_values
    refute TavernKit::Coerce.bool(false, default: true)
    refute TavernKit::Coerce.bool("0", default: true)
    refute TavernKit::Coerce.bool("false", default: true)
    refute TavernKit::Coerce.bool("no", default: true)
  end

  def test_bool_nil_returns_default
    assert TavernKit::Coerce.bool(nil, default: true)
    refute TavernKit::Coerce.bool(nil, default: false)
  end

  def test_generation_type_from_symbol
    assert_equal :normal, TavernKit::Coerce.generation_type(:normal)
    assert_equal :continue, TavernKit::Coerce.generation_type(:continue)
    assert_equal :impersonate, TavernKit::Coerce.generation_type(:impersonate)
  end

  def test_generation_type_from_integer
    assert_equal :normal, TavernKit::Coerce.generation_type(0)
    assert_equal :continue, TavernKit::Coerce.generation_type(1)
    assert_equal :quiet, TavernKit::Coerce.generation_type(5)
  end

  def test_generation_type_from_string
    assert_equal :normal, TavernKit::Coerce.generation_type("normal")
    assert_equal :continue, TavernKit::Coerce.generation_type("CONTINUE")
    assert_equal :normal, TavernKit::Coerce.generation_type("0")
  end

  def test_generation_type_default
    assert_equal :normal, TavernKit::Coerce.generation_type(nil)
    assert_equal :normal, TavernKit::Coerce.generation_type("")
    assert_equal :normal, TavernKit::Coerce.generation_type("unknown")
  end

  def test_triggers
    assert_equal [:normal, :continue], TavernKit::Coerce.triggers([0, 1])
    assert_equal [:normal], TavernKit::Coerce.triggers([:normal])
    assert_equal [], TavernKit::Coerce.triggers(nil)
    assert_equal [], TavernKit::Coerce.triggers([])
  end

  def test_role_from_symbol
    assert_equal :system, TavernKit::Coerce.role("system")
    assert_equal :user, TavernKit::Coerce.role("user")
    assert_equal :assistant, TavernKit::Coerce.role("assistant")
  end

  def test_role_from_integer
    assert_equal :system, TavernKit::Coerce.role(0)
    assert_equal :user, TavernKit::Coerce.role(1)
    assert_equal :assistant, TavernKit::Coerce.role(2)
  end

  def test_role_default
    assert_equal :system, TavernKit::Coerce.role(nil)
    assert_equal :user, TavernKit::Coerce.role(nil, default: :user)
  end

  def test_authors_note_position
    assert_equal :in_chat, TavernKit::Coerce.authors_note_position("in_chat")
    assert_equal :in_prompt, TavernKit::Coerce.authors_note_position("in_prompt")
    assert_equal :before_prompt, TavernKit::Coerce.authors_note_position("before_prompt")
    assert_equal :in_chat, TavernKit::Coerce.authors_note_position(1)
    assert_equal :in_prompt, TavernKit::Coerce.authors_note_position(0)
  end

  def test_authors_note_position_default
    assert_equal :in_chat, TavernKit::Coerce.authors_note_position(nil)
  end

  def test_insertion_strategy
    assert_equal :sorted_evenly, TavernKit::Coerce.insertion_strategy("sorted_evenly")
    assert_equal :character_lore_first, TavernKit::Coerce.insertion_strategy("character_lore_first")
    assert_equal :global_lore_first, TavernKit::Coerce.insertion_strategy("global_lore_first")
    assert_equal :sorted_evenly, TavernKit::Coerce.insertion_strategy(nil)
  end

  def test_examples_behavior
    assert_equal :gradually_push_out, TavernKit::Coerce.examples_behavior("gradually_push_out")
    assert_equal :always_keep, TavernKit::Coerce.examples_behavior("always_keep")
    assert_equal :disabled, TavernKit::Coerce.examples_behavior("disabled")
    assert_equal :gradually_push_out, TavernKit::Coerce.examples_behavior(nil)
  end
end
