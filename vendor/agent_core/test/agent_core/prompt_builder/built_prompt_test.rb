# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptBuilder::BuiltPromptTest < Minitest::Test
  class FakeTokenCounter
    attr_reader :messages_arg, :tools_arg

    def initialize
      @count_tools_called = false
    end

    def count_messages(messages)
      @messages_arg = messages
      10
    end

    def count_tools(tools)
      @count_tools_called = true
      @tools_arg = tools
      5
    end

    def count_tools_called?
      @count_tools_called
    end
  end

  def test_estimate_tokens_includes_system_prompt_and_tools
    counter = FakeTokenCounter.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "System",
      messages: [AgentCore::Message.new(role: :user, content: "Hi")],
      tools: [{ name: "read", description: "Read", parameters: {} }],
      options: { model: "test" }
    )

    est = prompt.estimate_tokens(token_counter: counter)

    assert_equal({ messages: 10, tools: 5, total: 15 }, est)
    assert_equal :system, counter.messages_arg.first.role
    assert_equal "System", counter.messages_arg.first.text
    assert_equal :user, counter.messages_arg[1].role
    assert counter.count_tools_called?
    assert_equal [{ name: "read", description: "Read", parameters: {} }], counter.tools_arg
  end

  def test_estimate_tokens_does_not_call_count_tools_when_no_tools
    counter = FakeTokenCounter.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "System",
      messages: [AgentCore::Message.new(role: :user, content: "Hi")],
      tools: [],
      options: {}
    )

    est = prompt.estimate_tokens(token_counter: counter)

    assert_equal({ messages: 10, tools: 0, total: 10 }, est)
    refute counter.count_tools_called?
  end

  def test_estimate_tokens_skips_blank_system_prompt
    counter = FakeTokenCounter.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "",
      messages: [AgentCore::Message.new(role: :user, content: "Hi")],
      options: {}
    )

    prompt.estimate_tokens(token_counter: counter)

    assert_equal 1, counter.messages_arg.size
    assert_equal :user, counter.messages_arg.first.role
  end
end
