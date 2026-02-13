# frozen_string_literal: true

require "test_helper"

class AgentCore::UtilsTest < Minitest::Test
  def test_symbolize_keys_nil
    assert_equal({}, AgentCore::Utils.symbolize_keys(nil))
  end

  def test_symbolize_keys_string_key
    assert_equal({ model: "m" }, AgentCore::Utils.symbolize_keys({ "model" => "m" }))
  end

  def test_symbolize_keys_symbol_wins_over_string
    input = { model: "a", "model" => "b" }
    assert_equal({ model: "a" }, AgentCore::Utils.symbolize_keys(input))
  end
end
