# frozen_string_literal: true

require "test_helper"

class TavernKit::RuntimeTest < Minitest::Test
  def test_base_build_normalizes_keys_to_snake_case_symbols
    runtime = TavernKit::Runtime::Base.build({ "chatIndex" => 1, message_index: 2 })
    assert_equal({ chat_index: 1, message_index: 2 }, runtime.to_h)
    assert_equal 1, runtime[:chat_index]
    assert_equal 2, runtime[:message_index]
  end

  def test_base_build_ignores_blank_keys
    runtime = TavernKit::Runtime::Base.build({ nil => 1, "" => 2, " " => 3, "ok" => 4 })
    assert_equal({ ok: 4 }, runtime.to_h)
  end
end
