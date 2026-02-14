# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::TokenCounter::HeuristicTest < Minitest::Test
  def setup
    @counter = AgentCore::Resources::TokenCounter::Heuristic.new
  end

  def test_count_text_basic
    # "Hello, world!" = 13 chars → ceil(13/4.0) = 4
    assert_equal 4, @counter.count_text("Hello, world!")
  end

  def test_count_text_empty_string
    assert_equal 0, @counter.count_text("")
  end

  def test_count_text_nil
    assert_equal 0, @counter.count_text(nil)
  end

  def test_count_text_exact_boundary
    # 8 chars → ceil(8/4.0) = 2
    assert_equal 2, @counter.count_text("12345678")
  end

  def test_custom_chars_per_token
    counter = AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: 2.0)
    # 10 chars → ceil(10/2.0) = 5
    assert_equal 5, counter.count_text("1234567890")
  end

  def test_invalid_chars_per_token_raises
    assert_raises(ArgumentError) do
      AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: 0)
    end

    assert_raises(ArgumentError) do
      AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: -1)
    end
  end

  def test_count_messages
    msgs = [
      AgentCore::Message.new(role: :user, content: "Hello!"),       # 6 chars → 2 tokens + 4 overhead = 6
      AgentCore::Message.new(role: :assistant, content: "Hi there!") # 9 chars → 3 tokens + 4 overhead = 7
    ]
    result = @counter.count_messages(msgs)
    assert_equal 13, result
  end

  def test_count_messages_empty
    assert_equal 0, @counter.count_messages([])
    assert_equal 0, @counter.count_messages(nil)
  end

  def test_count_tools
    tools = [
      { name: "read", description: "Read a file", parameters: { type: "object" } }
    ]
    result = @counter.count_tools(tools)
    assert result > 0
  end

  def test_count_tools_empty
    assert_equal 0, @counter.count_tools([])
    assert_equal 0, @counter.count_tools(nil)
  end
end

class AgentCore::Resources::TokenCounter::BaseTest < Minitest::Test
  def test_count_text_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) do
      AgentCore::Resources::TokenCounter::Base.new.count_text("hello")
    end
  end

  def test_count_messages_delegates_to_count_text
    # Create a simple counter that always returns text length
    counter = Class.new(AgentCore::Resources::TokenCounter::Base) do
      def count_text(text)
        text.to_s.length
      end
    end.new

    msgs = [AgentCore::Message.new(role: :user, content: "ab")]
    # "ab" = 2 chars + 4 overhead = 6
    assert_equal 6, counter.count_messages(msgs)
  end
end
