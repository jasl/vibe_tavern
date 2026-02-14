# frozen_string_literal: true

require "test_helper"

class AgentCore::AgentTest < Minitest::Test
  def test_build_and_chat
    agent = AgentCore::Agent.build do |b|
      b.name = "TestBot"
      b.system_prompt = "You are a test bot."
      b.provider = MockProvider.new
    end

    result = agent.chat("Hello!")

    assert_equal "Mock response", result.text
    assert_equal 1, result.turns
    # History should have user message + assistant message
    assert_equal 2, agent.chat_history.size
  end

  def test_build_requires_provider
    assert_raises(AgentCore::ConfigurationError) do
      AgentCore::Agent.build do |b|
        b.name = "NoProvider"
      end
    end
  end

  def test_serialization_roundtrip
    original = AgentCore::Agent.build do |b|
      b.name = "Serializable"
      b.description = "A test agent"
      b.system_prompt = "You are helpful."
      b.model = "test-model"
      b.max_turns = 5
      b.provider = MockProvider.new
    end

    config = original.to_config

    restored = AgentCore::Agent.from_config(
      config,
      provider: MockProvider.new
    )

    assert_equal "Serializable", restored.name
    assert_equal "A test agent", restored.description
    assert_equal "You are helpful.", restored.system_prompt
    assert_equal "test-model", restored.model
    assert_equal 5, restored.max_turns
  end

  def test_chat_with_tools
    echo_tool = AgentCore::Resources::Tools::Tool.new(
      name: "echo",
      description: "Echo",
      parameters: { type: "object", properties: { text: { type: "string" } } }
    ) { |args, context:| AgentCore::Resources::Tools::ToolResult.success(text: args[:text] || "") }

    # First response triggers tool call
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { text: "hi" })
    tool_msg = AgentCore::Message.new(role: :assistant, content: "Echoing...", tool_calls: [tc])
    tool_resp = AgentCore::Resources::Provider::Response.new(
      message: tool_msg, stop_reason: :tool_use,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 5)
    )

    # Second response is final
    final_msg = AgentCore::Message.new(role: :assistant, content: "Echo: hi")
    final_resp = AgentCore::Resources::Provider::Response.new(
      message: final_msg, stop_reason: :end_turn,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 15, output_tokens: 10)
    )

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(echo_tool)

    agent = AgentCore::Agent.build do |b|
      b.name = "ToolBot"
      b.system_prompt = "You have tools."
      b.provider = MockProvider.new(responses: [tool_resp, final_resp])
      b.tools_registry = registry
    end

    result = agent.chat("Echo hi")

    assert_equal "Echo: hi", result.text
    assert result.used_tools?
  end

  def test_chat_stream
    agent = AgentCore::Agent.build do |b|
      b.name = "StreamBot"
      b.system_prompt = "You are helpful."
      b.provider = MockProvider.new
    end

    events = []
    result = agent.chat_stream("Hello!") { |event| events << event }

    assert result.is_a?(AgentCore::PromptRunner::RunResult)
    assert events.any?
    assert events.any? { |e| e.type == :text_delta }
  end

  def test_reset_clears_history
    agent = AgentCore::Agent.build do |b|
      b.provider = MockProvider.new
    end

    agent.chat("Hello!")
    assert agent.chat_history.size > 0

    agent.reset!
    assert agent.chat_history.empty?
  end

  def test_convenience_build
    agent = AgentCore.build do |b|
      b.provider = MockProvider.new
    end

    assert_instance_of AgentCore::Agent, agent
  end

  def test_with_memory
    memory = AgentCore::Resources::Memory::InMemory.new
    memory.store(content: "User's favorite color is blue")

    agent = AgentCore::Agent.build do |b|
      b.system_prompt = "You are helpful."
      b.provider = MockProvider.new
      b.memory = memory
    end

    # Should not raise — memory integration is transparent
    result = agent.chat("What's my favorite color?")
    assert result.text
  end

  def test_memory_injected_into_system_message
    memory = AgentCore::Resources::Memory::InMemory.new
    memory.store(content: "User's favorite color is blue")

    provider = MockProvider.new
    agent = AgentCore::Agent.build do |b|
      b.system_prompt = "You are helpful."
      b.provider = provider
      b.memory = memory
    end

    agent.chat("favorite")

    system_message = provider.calls.first[:messages].first
    assert_equal :system, system_message.role
    assert_includes system_message.text, "User's favorite color is blue"
    assert_includes system_message.text, "<relevant_context>"
  end

  def test_multi_turn_conversation
    provider = MockProvider.new

    agent = AgentCore::Agent.build do |b|
      b.provider = provider
    end

    agent.chat("First message")
    agent.chat("Second message")

    # Should have 4 messages in history (2 user + 2 assistant)
    assert_equal 4, agent.chat_history.size

    # Provider should have received the full history on second call
    second_call = provider.calls.last
    # Messages should include prior history + new user message
    assert second_call[:messages].size > 1
  end

  def test_chat_with_token_counter_raises_on_exceed
    counter = AgentCore::Resources::TokenCounter::Heuristic.new
    provider = MockProvider.new

    agent = AgentCore::Agent.build do |b|
      b.provider = provider
      b.system_prompt = "You are helpful."
      b.token_counter = counter
      b.context_window = 10  # very small
      b.reserved_output_tokens = 0
    end

    assert_raises(AgentCore::ContextWindowExceededError) do
      agent.chat("This message should exceed the tiny context window")
    end

    # Provider should not have been called
    assert_equal 0, provider.calls.size
  end

  def test_chat_with_token_counter_succeeds_within_budget
    counter = AgentCore::Resources::TokenCounter::Heuristic.new
    provider = MockProvider.new

    agent = AgentCore::Agent.build do |b|
      b.provider = provider
      b.system_prompt = "Hi"
      b.token_counter = counter
      b.context_window = 100_000
      b.reserved_output_tokens = 4096
    end

    result = agent.chat("Hello")
    assert_equal "Mock response", result.text
    assert_equal 1, provider.calls.size
  end

  def test_build_rejects_invalid_token_budget_config
    assert_raises(AgentCore::ConfigurationError) do
      AgentCore::Agent.build do |b|
        b.provider = MockProvider.new
        b.context_window = 0
      end
    end

    assert_raises(AgentCore::ConfigurationError) do
      AgentCore::Agent.build do |b|
        b.provider = MockProvider.new
        b.reserved_output_tokens = -1
      end
    end

    assert_raises(AgentCore::ConfigurationError) do
      AgentCore::Agent.build do |b|
        b.provider = MockProvider.new
        b.context_window = 100
        b.reserved_output_tokens = 100
      end
    end
  end

  def test_build_rejects_token_counter_without_required_interface
    bad_counter = Class.new do
      def count_messages(_messages)
        0
      end
    end.new

    assert_raises(AgentCore::ConfigurationError) do
      AgentCore::Agent.build do |b|
        b.provider = MockProvider.new
        b.token_counter = bad_counter
      end
    end
  end

  def test_from_config_nil_reserved_output_tokens_is_treated_as_zero
    config = {
      name: "NilReserved",
      context_window: 10_000,
      reserved_output_tokens: nil,
    }

    agent = AgentCore::Agent.from_config(config, provider: MockProvider.new)
    assert_equal 0, agent.reserved_output_tokens
  end

  def test_config_roundtrip_with_token_budget
    provider = MockProvider.new

    agent = AgentCore::Agent.build do |b|
      b.provider = provider
      b.context_window = 200_000
      b.reserved_output_tokens = 8192
    end

    config = agent.to_config
    assert_equal 200_000, config[:context_window]
    assert_equal 8192, config[:reserved_output_tokens]

    restored = AgentCore::Agent.from_config(config, provider: provider)
    assert_equal 200_000, restored.context_window
    assert_equal 8192, restored.reserved_output_tokens
  end
end
