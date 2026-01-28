# frozen_string_literal: true

require "test_helper"

class TavernKit::ErrorsTest < Minitest::Test
  def test_error_hierarchy
    assert TavernKit::Error < StandardError
    assert TavernKit::StrictModeError < TavernKit::Error
    assert TavernKit::InvalidCardError < TavernKit::Error
    assert TavernKit::UnsupportedVersionError < TavernKit::Error
    assert TavernKit::Png::ParseError < TavernKit::Error
    assert TavernKit::Png::WriteError < TavernKit::Error
    assert TavernKit::Lore::ParseError < TavernKit::Error
  end

  def test_errors_can_be_raised_and_rescued
    assert_raises(TavernKit::Error) { raise TavernKit::InvalidCardError, "bad card" }
    assert_raises(TavernKit::Error) { raise TavernKit::StrictModeError, "strict" }
    assert_raises(TavernKit::Error) { raise TavernKit::Png::ParseError, "png" }
    assert_raises(TavernKit::Error) { raise TavernKit::Png::WriteError, "write" }
    assert_raises(TavernKit::Error) { raise TavernKit::Lore::ParseError, "lore" }
  end

  def test_error_messages
    error = TavernKit::InvalidCardError.new("missing name field")
    assert_equal "missing name field", error.message
  end
end
