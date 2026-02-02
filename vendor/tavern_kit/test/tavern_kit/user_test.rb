# frozen_string_literal: true

require "test_helper"

class TavernKit::UserTest < Minitest::Test
  def test_user_is_data_define
    assert TavernKit::User < Data
  end

  def test_user_with_name_only
    user = TavernKit::User.new(name: "Alice")
    assert_equal "Alice", user.name
    assert_nil user.persona
    assert_equal "", user.persona_text
  end

  def test_user_with_name_and_persona
    user = TavernKit::User.new(name: "Alice", persona: "A curious adventurer")
    assert_equal "Alice", user.name
    assert_equal "A curious adventurer", user.persona
    assert_equal "A curious adventurer", user.persona_text
  end

  def test_user_implements_participant
    user = TavernKit::User.new(name: "Alice")
    assert_kind_of TavernKit::Participant, user
    assert_respond_to user, :name
    assert_respond_to user, :persona_text
  end

  def test_user_is_immutable
    user = TavernKit::User.new(name: "Alice", persona: "test")
    assert user.frozen?
  end

  def test_user_equality
    u1 = TavernKit::User.new(name: "Alice", persona: "test")
    u2 = TavernKit::User.new(name: "Alice", persona: "test")
    assert_equal u1, u2
  end

  def test_user_nil_persona_text
    user = TavernKit::User.new(name: "Bob", persona: nil)
    assert_equal "", user.persona_text
  end
end
