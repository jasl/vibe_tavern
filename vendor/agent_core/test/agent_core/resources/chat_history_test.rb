# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::ChatHistory::InMemoryTest < Minitest::Test
  def setup
    @history = AgentCore::Resources::ChatHistory::InMemory.new
  end

  def test_starts_empty
    assert @history.empty?
    assert_equal 0, @history.size
  end

  def test_append_and_iterate
    msg1 = AgentCore::Message.new(role: :user, content: "Hello")
    msg2 = AgentCore::Message.new(role: :assistant, content: "Hi!")

    @history.append(msg1)
    @history.append(msg2)

    assert_equal 2, @history.size
    messages = @history.to_a
    assert_equal :user, messages[0].role
    assert_equal :assistant, messages[1].role
  end

  def test_last
    3.times { |i| @history.append(AgentCore::Message.new(role: :user, content: "msg #{i}")) }

    last_two = @history.last(2)
    assert_equal 2, last_two.size
    assert_equal "msg 1", last_two[0].text
    assert_equal "msg 2", last_two[1].text
  end

  def test_clear
    @history.append(AgentCore::Message.new(role: :user, content: "hi"))
    assert_equal 1, @history.size

    @history.clear
    assert @history.empty?
  end

  def test_append_many
    msgs = [
      AgentCore::Message.new(role: :user, content: "a"),
      AgentCore::Message.new(role: :assistant, content: "b"),
    ]
    @history.append_many(msgs)
    assert_equal 2, @history.size
  end

  def test_shovel_operator
    @history << AgentCore::Message.new(role: :user, content: "hi")
    assert_equal 1, @history.size
  end

  def test_enumerable
    @history.append(AgentCore::Message.new(role: :user, content: "hi"))
    @history.append(AgentCore::Message.new(role: :assistant, content: "hello"))

    user_msgs = @history.select(&:user?)
    assert_equal 1, user_msgs.size
  end

  def test_thread_safety
    threads = 10.times.map do |i|
      Thread.new do
        100.times { |j| @history.append(AgentCore::Message.new(role: :user, content: "#{i}-#{j}")) }
      end
    end
    threads.each(&:join)

    assert_equal 1000, @history.size
  end

  def test_initialize_with_messages
    msgs = [AgentCore::Message.new(role: :user, content: "initial")]
    history = AgentCore::Resources::ChatHistory::InMemory.new(msgs)
    assert_equal 1, history.size
  end

  def test_replace_message_by_identity
    msg1 = AgentCore::Message.new(role: :user, content: "Hello")
    msg2 = AgentCore::Message.new(role: :assistant, content: "Hi!")

    @history.append(msg1)
    @history.append(msg2)

    replacement = AgentCore::Message.new(role: :assistant, content: "Rewritten")

    assert @history.replace_message(msg2, replacement)
    assert_same replacement, @history.last.first

    missing = AgentCore::Message.new(role: :assistant, content: "missing")
    assert_equal false, @history.replace_message(missing, replacement)
  end
end

class AgentCore::Resources::ChatHistory::WrapTest < Minitest::Test
  def test_wrap_nil
    history = AgentCore::Resources::ChatHistory.wrap(nil)
    assert_instance_of AgentCore::Resources::ChatHistory::InMemory, history
    assert history.empty?
  end

  def test_wrap_array
    msgs = [AgentCore::Message.new(role: :user, content: "hi")]
    history = AgentCore::Resources::ChatHistory.wrap(msgs)
    assert_instance_of AgentCore::Resources::ChatHistory::InMemory, history
    assert_equal 1, history.size
  end

  def test_wrap_base
    original = AgentCore::Resources::ChatHistory::InMemory.new
    assert_same original, AgentCore::Resources::ChatHistory.wrap(original)
  end

  def test_wrap_invalid
    assert_raises(ArgumentError) do
      AgentCore::Resources::ChatHistory.wrap(42)
    end
  end
end
