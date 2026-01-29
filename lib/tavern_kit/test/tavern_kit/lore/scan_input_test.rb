# frozen_string_literal: true

require "test_helper"

class TavernKit::Lore::ScanInputTest < Minitest::Test
  def test_initializer
    input = TavernKit::Lore::ScanInput.new(messages: [1], books: [2], budget: 100, extra: "ignored")
    assert_equal [1], input.messages
    assert_equal [2], input.books
    assert_equal 100, input.budget
  end
end
