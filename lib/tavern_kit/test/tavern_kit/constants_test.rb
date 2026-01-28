# frozen_string_literal: true

require "test_helper"

class TavernKit::ConstantsTest < Minitest::Test
  def test_generation_types_frozen
    assert TavernKit::GENERATION_TYPES.frozen?
  end

  def test_generation_types_values
    expected = %i[normal continue impersonate swipe regenerate quiet]
    assert_equal expected, TavernKit::GENERATION_TYPES
  end

  def test_trigger_code_map_frozen
    assert TavernKit::TRIGGER_CODE_MAP.frozen?
  end

  def test_trigger_code_map_values
    assert_equal :normal, TavernKit::TRIGGER_CODE_MAP[0]
    assert_equal :continue, TavernKit::TRIGGER_CODE_MAP[1]
    assert_equal :impersonate, TavernKit::TRIGGER_CODE_MAP[2]
    assert_equal :swipe, TavernKit::TRIGGER_CODE_MAP[3]
    assert_equal :regenerate, TavernKit::TRIGGER_CODE_MAP[4]
    assert_equal :quiet, TavernKit::TRIGGER_CODE_MAP[5]
  end
end
