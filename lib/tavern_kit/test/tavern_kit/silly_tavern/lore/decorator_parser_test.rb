# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Lore::DecoratorParserTest < Minitest::Test
  def test_returns_original_content_when_no_decorators
    decorators, content = TavernKit::SillyTavern::Lore::DecoratorParser.parse("Hello")
    assert_equal [], decorators
    assert_equal "Hello", content
  end

  def test_parses_single_activate_decorator
    decorators, content = TavernKit::SillyTavern::Lore::DecoratorParser.parse("@@activate\nBody\n")
    assert_equal ["@@activate"], decorators
    assert_equal "Body\n", content
  end

  def test_parses_multiple_known_decorators
    decorators, content = TavernKit::SillyTavern::Lore::DecoratorParser.parse("@@activate\n@@dont_activate\nBody")
    assert_equal ["@@activate", "@@dont_activate"], decorators
    assert_equal "Body", content
  end

  def test_unknown_decorators_are_treated_as_content
    decorators, content = TavernKit::SillyTavern::Lore::DecoratorParser.parse("@@unknown\nBody")
    assert_equal [], decorators
    assert_equal "@@unknown\nBody", content
  end
end
