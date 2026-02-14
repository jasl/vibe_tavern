# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptRunner::RunnerTest < Minitest::Test
  def setup
    @runner = AgentCore::PromptRunner::Runner.new
  end

  def test_simple_run
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are helpful.",
      messages: [AgentCore::Message.new(role: :user, content: "Hello")],
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider)

    assert_equal "Mock response", result.text
    assert_equal 1, result.turns
    assert_equal :end_turn, result.stop_reason
    refute result.used_tools?
  end

  def test_system_prompt_is_sent_as_system_message
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "System instructions",
      messages: [AgentCore::Message.new(role: :user, content: "Hello")],
      options: { model: "test" }
    )

    @runner.run(prompt: prompt, provider: provider)

    call_messages = provider.calls.first[:messages]
    assert_equal :system, call_messages.first.role
    assert_equal "System instructions", call_messages.first.text
  end

  def test_run_with_tool_calling
    # First response: assistant wants to call a tool
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { text: "hello" })
    assistant_with_tool = AgentCore::Message.new(
      role: :assistant,
      content: "Let me echo that.",
      tool_calls: [tool_call]
    )
    tool_response = AgentCore::Resources::Provider::Response.new(
      message: assistant_with_tool,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 5),
      stop_reason: :tool_use
    )

    # Second response: final text
    final_msg = AgentCore::Message.new(role: :assistant, content: "Echo result: hello")
    final_response = AgentCore::Resources::Provider::Response.new(
      message: final_msg,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 15, output_tokens: 10),
      stop_reason: :end_turn
    )

    provider = MockProvider.new(responses: [tool_response, final_response])

    # Set up tools
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, context:|
        AgentCore::Resources::Tools::ToolResult.success(text: args[:text] || args["text"] || "")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are helpful.",
      messages: [AgentCore::Message.new(role: :user, content: "Echo hello")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry)

    assert_equal "Echo result: hello", result.text
    assert_equal 2, result.turns
    assert result.used_tools?
    assert_equal 1, result.tool_calls_made.size
    assert_equal "echo", result.tool_calls_made.first[:name]
  end

  def test_unknown_tool_call_does_not_raise
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "missing_tool", arguments: {})
    assistant_with_tool = AgentCore::Message.new(
      role: :assistant,
      content: "Calling a missing tool",
      tool_calls: [tool_call]
    )
    tool_response = AgentCore::Resources::Provider::Response.new(
      message: assistant_with_tool,
      stop_reason: :tool_use
    )

    final_msg = AgentCore::Message.new(role: :assistant, content: "Recovered")
    final_response = AgentCore::Resources::Provider::Response.new(
      message: final_msg,
      stop_reason: :end_turn
    )

    provider = MockProvider.new(responses: [tool_response, final_response])
    registry = AgentCore::Resources::Tools::Registry.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry)

    assert_equal "Recovered", result.text
    assert_equal 1, result.tool_calls_made.size
    assert_match(/Tool not found:/, result.tool_calls_made.first[:error])
  end

  def test_max_turns_limit
    # Provider always returns tool calls — will hit max turns
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { text: "loop" })
    looping_msg = AgentCore::Message.new(role: :assistant, content: "calling...", tool_calls: [tool_call])
    looping_response = AgentCore::Resources::Provider::Response.new(
      message: looping_msg,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 5, output_tokens: 5),
      stop_reason: :tool_use
    )

    # Create enough responses to exceed max_turns
    provider = MockProvider.new(responses: Array.new(5, looping_response))

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, context:|
        AgentCore::Resources::Tools::ToolResult.success(text: "echoed")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "go")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, max_turns: 3)

    assert result.max_turns_reached?
    assert_equal :max_turns, result.stop_reason
  end

  def test_events_are_emitted
    provider = MockProvider.new
    events = AgentCore::PromptRunner::Events.new

    turn_starts = []
    events.on_turn_start { |turn| turn_starts << turn }

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      options: { model: "test" }
    )

    @runner.run(prompt: prompt, provider: provider, events: events)

    assert_equal [1], turn_starts
  end

  def test_tool_policy_deny
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "dangerous", arguments: {})
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(
      message: assistant_msg,
      stop_reason: :tool_use
    )

    final_msg = AgentCore::Message.new(role: :assistant, content: "Tool was denied.")
    final_response = AgentCore::Resources::Provider::Response.new(
      message: final_msg,
      stop_reason: :end_turn
    )

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "dangerous", description: "bad", parameters: {}) do |args, context:|
        AgentCore::Resources::Tools::ToolResult.success(text: "should not run")
      end
    )

    # Custom policy that denies "dangerous" tool
    deny_policy = Class.new(AgentCore::Resources::Tools::Policy::Base) do
      def authorize(name:, arguments: {}, context: {})
        if name == "dangerous"
          AgentCore::Resources::Tools::Policy::Decision.deny(reason: "too risky")
        else
          AgentCore::Resources::Tools::Policy::Decision.allow
        end
      end
    end.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "do something dangerous")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: deny_policy)

    assert_equal 1, result.tool_calls_made.size
    assert_equal "too risky", result.tool_calls_made.first[:error]
  end

  def test_streaming_run
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      options: { model: "test" }
    )

    events_received = []
    result = @runner.run_stream(prompt: prompt, provider: provider) do |event|
      events_received << event
    end

    assert result.is_a?(AgentCore::PromptRunner::RunResult)
    # Should have received text_delta, message_complete, done, turn events
    event_types = events_received.map(&:type)
    assert_includes event_types, :turn_start
    assert_includes event_types, :text_delta
    assert_includes event_types, :done
  end

  def test_max_turns_zero_raises
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      options: { model: "test" }
    )

    assert_raises(ArgumentError) do
      @runner.run(prompt: prompt, provider: MockProvider.new, max_turns: 0)
    end
  end

  def test_max_turns_negative_raises
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      options: { model: "test" }
    )

    assert_raises(ArgumentError) do
      @runner.run_stream(prompt: prompt, provider: MockProvider.new, max_turns: -1) { }
    end
  end

  def test_nil_response_message_returns_error
    # Provider that returns nil message
    nil_msg_provider = Class.new(AgentCore::Resources::Provider::Base) do
      define_method(:chat) do |messages:, model:, tools: nil, stream: false, **options|
        AgentCore::Resources::Provider::Response.new(
          message: nil,
          stop_reason: :end_turn
        )
      end
      define_method(:name) { "nil_msg" }
    end.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: nil_msg_provider)
    assert_equal :error, result.stop_reason
  end

  # --- Token budget preflight tests ---

  def test_no_token_counter_runs_normally
    # Backward compatibility: no token_counter = no check
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider)
    assert_equal "Mock response", result.text
  end

  def test_preflight_raises_when_exceeding_context_window
    counter = AgentCore::Resources::TokenCounter::Heuristic.new
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are a helpful assistant.",
      messages: [AgentCore::Message.new(role: :user, content: "Hello " * 100)],
      options: { model: "test" }
    )

    err = assert_raises(AgentCore::ContextWindowExceededError) do
      @runner.run(
        prompt: prompt, provider: provider,
        token_counter: counter, context_window: 10, reserved_output_tokens: 0
      )
    end

    assert err.estimated_tokens > 10
    assert_equal 10, err.context_window
    # Provider should NOT have been called
    assert_equal 0, provider.calls.size
  end

  def test_preflight_passes_when_within_budget
    counter = AgentCore::Resources::TokenCounter::Heuristic.new
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "Hi",
      messages: [AgentCore::Message.new(role: :user, content: "Hello")],
      options: { model: "test" }
    )

    result = @runner.run(
      prompt: prompt, provider: provider,
      token_counter: counter, context_window: 100_000, reserved_output_tokens: 1000
    )

    assert_equal "Mock response", result.text
    assert_equal 1, provider.calls.size
  end

  def test_preflight_accounts_for_reserved_output_tokens
    counter = AgentCore::Resources::TokenCounter::Heuristic.new
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "System",
      messages: [AgentCore::Message.new(role: :user, content: "Hi")],
      options: { model: "test" }
    )

    # Estimate is small, but with large reserved_output it should exceed
    # "System" + "Hi" ~= 2 + 4 + 1 + 4 = ~11 tokens
    # context_window: 15, reserved: 10 → limit = 5 → should exceed
    assert_raises(AgentCore::ContextWindowExceededError) do
      @runner.run(
        prompt: prompt, provider: provider,
        token_counter: counter, context_window: 15, reserved_output_tokens: 10
      )
    end
  end

  def test_per_turn_usage_tracked
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider)
    assert_equal 1, result.per_turn_usage.size
    assert_equal 10, result.per_turn_usage.first.input_tokens
    assert_equal 5, result.per_turn_usage.first.output_tokens
  end

  def test_preflight_stream_raises_when_exceeding
    counter = AgentCore::Resources::TokenCounter::Heuristic.new
    provider = MockProvider.new
    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "x" * 1000,
      messages: [AgentCore::Message.new(role: :user, content: "y" * 1000)],
      options: { model: "test" }
    )

    assert_raises(AgentCore::ContextWindowExceededError) do
      @runner.run_stream(
        prompt: prompt, provider: provider,
        token_counter: counter, context_window: 50, reserved_output_tokens: 0
      ) { }
    end

    assert_equal 0, provider.calls.size
  end
end

class AgentCore::PromptRunner::EventsTest < Minitest::Test
  def test_register_and_emit
    events = AgentCore::PromptRunner::Events.new
    received = []

    events.on_turn_start { |turn| received << turn }
    events.emit(:turn_start, 1)
    events.emit(:turn_start, 2)

    assert_equal [1, 2], received
  end

  def test_multiple_listeners
    events = AgentCore::PromptRunner::Events.new
    a = []
    b = []

    events.on_turn_start { |t| a << t }
    events.on_turn_start { |t| b << t }
    events.emit(:turn_start, 1)

    assert_equal [1], a
    assert_equal [1], b
  end

  def test_callback_error_does_not_propagate
    events = AgentCore::PromptRunner::Events.new
    events.on_turn_start { raise "boom" }

    errors = []
    events.on_error { |e, _| errors << e.message }

    # Should not raise
    events.emit(:turn_start, 1)
    assert_equal ["boom"], errors
  end

  def test_has_listeners
    events = AgentCore::PromptRunner::Events.new
    refute events.has_listeners?(:turn_start)

    events.on_turn_start { }
    assert events.has_listeners?(:turn_start)
  end

  def test_generic_on_method
    events = AgentCore::PromptRunner::Events.new
    received = []

    events.on(:turn_start) { |t| received << t }
    events.emit(:turn_start, 42)

    assert_equal [42], received
  end

  def test_generic_on_unknown_hook_raises
    events = AgentCore::PromptRunner::Events.new

    assert_raises(ArgumentError) do
      events.on(:nonexistent) { }
    end
  end

  def test_per_callback_rescue_continues_to_next
    events = AgentCore::PromptRunner::Events.new
    results = []

    events.on_turn_start { raise "first fails" }
    events.on_turn_start { |t| results << t }

    errors = []
    events.on_error { |e, _| errors << e.message }

    events.emit(:turn_start, 1)

    # Second callback should still run despite first failing
    assert_equal [1], results
    assert_equal ["first fails"], errors
  end
end
