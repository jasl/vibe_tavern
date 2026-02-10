# frozen_string_literal: true

require "test_helper"

class TavernKit::ContextTest < Minitest::Test
  def test_base_build_normalizes_keys_to_snake_case_symbols
    context = TavernKit::PromptBuilder::Context.build({ "chatIndex" => 1, message_index: 2 })
    assert_equal({ chat_index: 1, message_index: 2 }, context.to_h)
    assert_equal 1, context[:chat_index]
    assert_equal 2, context[:message_index]
  end

  def test_base_build_ignores_blank_keys
    context = TavernKit::PromptBuilder::Context.build({ nil => 1, "" => 2, " " => 3, "ok" => 4 })
    assert_equal({ ok: 4 }, context.to_h)
  end
end
