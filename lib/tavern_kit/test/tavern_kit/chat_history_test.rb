# frozen_string_literal: true

require "test_helper"

class TavernKit::ChatHistoryTest < Minitest::Test
  def test_wrap_nil_returns_empty_in_memory
    history = TavernKit::ChatHistory.wrap(nil)
    assert_instance_of TavernKit::ChatHistory::InMemory, history
    assert_equal 0, history.size
  end

  def test_wrap_array_coerces_hashes_to_messages
    history = TavernKit::ChatHistory.wrap(
      [
        { "role" => "user", "content" => "hi" },
        { role: :assistant, content: "yo", name: "Bot" },
      ],
    )

    msgs = history.to_a
    assert_equal 2, msgs.size
    assert_instance_of TavernKit::Prompt::Message, msgs[0]
    assert_equal :user, msgs[0].role
    assert_equal "hi", msgs[0].content
    assert_equal :assistant, msgs[1].role
    assert_equal "yo", msgs[1].content
    assert_equal "Bot", msgs[1].name
  end

  def test_in_memory_append_and_last
    history = TavernKit::ChatHistory::InMemory.new
    history.append(role: :user, content: "a")
    history.append(role: :user, content: "b")

    assert_equal 2, history.size
    assert_equal ["b"], history.last(1).map(&:content)
  end
end
