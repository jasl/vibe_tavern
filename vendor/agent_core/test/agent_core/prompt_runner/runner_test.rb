# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptRunner::RunnerTest < Minitest::Test
  def setup
    @runner = AgentCore::PromptRunner::Runner.new
    @allow_all = AgentCore::Resources::Tools::Policy::AllowAll.new
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
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
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
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text", ""))
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are helpful.",
      messages: [AgentCore::Message.new(role: :user, content: "Echo hello")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    assert_equal "Echo result: hello", result.text
    assert_equal 2, result.turns
    assert result.used_tools?
    assert_equal 1, result.tool_calls_made.size
    assert_equal "echo", result.tool_calls_made.first[:name]
  end

  def test_deferred_tool_execution_pauses_without_executing_tool
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    provider = MockProvider.new(responses: [tool_response])

    executed = false
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        executed = true
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      )

    assert result.awaiting_tool_results?
    refute executed
    assert_equal 1, provider.calls.size

    assert_equal 1, result.pending_tool_executions.size
    pending = result.pending_tool_executions.first
    assert_equal "tc_1", pending.tool_call_id
    assert_equal "echo", pending.name
    assert_equal "echo", pending.executed_name

    assert_equal 1, result.tool_calls_made.size
    record = result.tool_calls_made.first
    assert_equal "tc_1", record.fetch(:tool_call_id)
    assert_equal true, record.fetch(:pending)
    assert_equal true, record.fetch(:deferred)
  end

  def test_resume_with_tool_results_continues_to_final
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      )

    assert paused.awaiting_tool_results?
    assert_equal 1, provider.calls.size

    resumed =
      @runner.resume_with_tool_results(
        continuation: paused.continuation,
        tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") },
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
      )

    assert_equal "Done", resumed.text
    assert_equal paused.run_id, resumed.run_id
    assert_equal 2, provider.calls.size

    tool_msg = resumed.messages.find(&:tool_result?)
    assert tool_msg
    assert_equal "ok", tool_msg.content

    assert_equal 1, resumed.tool_calls_made.size
    record = resumed.tool_calls_made.first
    assert_equal false, record.fetch(:pending)
    assert_equal false, record.fetch(:deferred)
    assert_equal true, record.fetch(:external)
  end

  def test_resume_with_tool_results_accepts_json_continuation_payload
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      )

    payload = AgentCore::PromptRunner::ContinuationCodec.dump(paused.continuation, include_traces: false)
    json = JSON.generate(payload)

    resumed =
      @runner.resume_with_tool_results(
        continuation: json,
        tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") },
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
      )

    assert_equal "Done", resumed.text
  end

  def test_partial_resume_with_tool_results_waits_until_all_results_are_available
    tool_call_1 = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    tool_call_2 = AgentCore::ToolCall.new(id: "tc_2", name: "echo", arguments: { "text" => "world" })
    assistant_with_tool =
      AgentCore::Message.new(
        role: :assistant,
        content: "Calling tool",
        tool_calls: [tool_call_1, tool_call_2],
      )
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    instrumenter = AgentCore::Observability::TraceRecorder.new(capture: :full)

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
        instrumenter: instrumenter,
      )

    assert paused.awaiting_tool_results?
    assert_equal 1, provider.calls.size
    refute_nil paused.continuation.continuation_id
    assert_nil paused.continuation.parent_continuation_id

    pause_events = instrumenter.trace.select { |e| e.fetch(:name) == "agent_core.pause" }
    assert_equal 1, pause_events.size
    pause_cid_1 = pause_events.first.fetch(:payload).fetch("continuation_id")
    assert_equal paused.continuation.continuation_id, pause_cid_1

    partial =
      @runner.resume_with_tool_results(
        continuation: paused.continuation,
        tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "r1") },
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        allow_partial: true,
        instrumenter: instrumenter,
      )

    assert partial.awaiting_tool_results?
    assert_equal 1, provider.calls.size
    assert_empty partial.messages
    refute_nil partial.continuation.continuation_id
    refute_equal paused.continuation.continuation_id, partial.continuation.continuation_id
    assert_equal paused.continuation.continuation_id, partial.continuation.parent_continuation_id

    assert_equal 1, partial.pending_tool_executions.size
    assert_equal "tc_2", partial.pending_tool_executions.first.tool_call_id
    assert partial.continuation.buffered_tool_results.key?("tc_1")

    pause_events = instrumenter.trace.select { |e| e.fetch(:name) == "agent_core.pause" }
    assert_equal 2, pause_events.size
    pause_cid_2 = pause_events.last.fetch(:payload).fetch("continuation_id")
    assert_equal partial.continuation.continuation_id, pause_cid_2
    refute_equal pause_cid_1, pause_cid_2
    assert_equal pause_cid_1, pause_events.last.fetch(:payload).fetch("parent_continuation_id")

    resume_events = instrumenter.trace.select { |e| e.fetch(:name) == "agent_core.resume" }
    assert_equal 1, resume_events.size
    assert_equal pause_cid_1, resume_events.first.fetch(:payload).fetch("continuation_id")

    payload = AgentCore::PromptRunner::ContinuationCodec.dump(partial.continuation, include_traces: false)
    loaded = AgentCore::PromptRunner::ContinuationCodec.load(JSON.generate(payload))

    final =
      @runner.resume_with_tool_results(
        continuation: loaded,
        tool_results: { "tc_2" => AgentCore::Resources::Tools::ToolResult.success(text: "r2") },
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        allow_partial: true,
        instrumenter: instrumenter,
      )

    assert_equal "Done", final.text
    assert_equal 2, provider.calls.size

    tool_msgs = final.messages.select(&:tool_result?)
    assert_equal %w[tc_1 tc_2], tool_msgs.map(&:tool_call_id)
    assert_equal %w[r1 r2], tool_msgs.map(&:content)

    resume_events = instrumenter.trace.select { |e| e.fetch(:name) == "agent_core.resume" }
    assert_equal 2, resume_events.size
    assert_equal pause_cid_2, resume_events.last.fetch(:payload).fetch("continuation_id")
  end

  def test_tool_task_created_and_deferred_events_do_not_include_raw_arguments
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    provider = MockProvider.new(responses: [tool_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    instrumenter = AgentCore::Observability::TraceRecorder.new(capture: :full)

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
        instrumenter: instrumenter,
      )

    assert paused.awaiting_tool_results?

    created = instrumenter.trace.find { |e| e.fetch(:name) == "agent_core.tool.task.created" }
    assert created
    payload = created.fetch(:payload)
    assert_equal paused.run_id, payload.fetch("run_id")
    assert_equal 1, payload.fetch("turn_number")
    assert_equal "tc_1", payload.fetch("tool_call_id")
    assert_equal "echo", payload.fetch("name")
    refute payload.key?("arguments")

    deferred = instrumenter.trace.find { |e| e.fetch(:name) == "agent_core.tool.task.deferred" }
    assert deferred
    refute deferred.fetch(:payload).key?("arguments")
  end

  def test_pause_and_resume_events_are_published
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    instrumenter = AgentCore::Observability::TraceRecorder.new(capture: :full)

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
        instrumenter: instrumenter,
      )

    pause_event = instrumenter.trace.find { |e| e.fetch(:name) == "agent_core.pause" }
    assert pause_event
    assert_equal paused.run_id, pause_event.fetch(:payload).fetch("run_id")
    assert_equal 1, pause_event.fetch(:payload).fetch("turn_number")
    assert_equal "awaiting_tool_results", pause_event.fetch(:payload).fetch("pause_reason")
    assert_equal paused.continuation.continuation_id, pause_event.fetch(:payload).fetch("continuation_id")
    assert_equal 0, pause_event.fetch(:payload).fetch("pending_confirmations_count")
    assert_equal 1, pause_event.fetch(:payload).fetch("pending_executions_count")

    resumed =
      @runner.resume_with_tool_results(
        continuation: paused.continuation,
        tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") },
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        instrumenter: instrumenter,
      )

    assert_equal "Done", resumed.text

    resume_event = instrumenter.trace.find { |e| e.fetch(:name) == "agent_core.resume" }
    assert resume_event
    assert_equal paused.run_id, resume_event.fetch(:payload).fetch("run_id")
    assert_equal 1, resume_event.fetch(:payload).fetch("paused_turn_number")
    assert_equal "awaiting_tool_results", resume_event.fetch(:payload).fetch("pause_reason")
    assert_equal paused.continuation.continuation_id, resume_event.fetch(:payload).fetch("continuation_id")
    assert_equal true, resume_event.fetch(:payload).fetch("resumed")
  end

  def test_tool_call_with_invalid_arguments_is_not_executed
    executed = false

    tool_call =
      AgentCore::ToolCall.new(
        id: "tc_1",
        name: "echo",
        arguments: {},
        arguments_parse_error: :invalid_json
      )
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        executed = true
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    refute executed
    assert_equal 1, result.tool_calls_made.size
    assert_equal "invalid_json", result.tool_calls_made.first[:error]
  end

  def test_tool_output_is_truncated_when_exceeding_limit
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "big", arguments: {})
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "big", description: "Big", parameters: {}) do |_args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: "a" * 1000)
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result =
      @runner.run(
        prompt: prompt, provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        max_tool_output_bytes: 100
      )

    tool_result_msg = result.messages.find(&:tool_result?)
    assert tool_result_msg
    assert_kind_of String, tool_result_msg.content
    assert_includes tool_result_msg.content, "[truncated]"
    assert_operator tool_result_msg.content.bytesize, :<=, 100
  end

  def test_dot_tool_name_falls_back_to_underscored_tool
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "foo.bar", arguments: {})
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    executed = []
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "foo_bar", description: "Foo", parameters: {}) do |_args, **|
        executed << :foo_bar
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    assert_equal [:foo_bar], executed
    assert_equal 1, result.tool_calls_made.size
    assert_equal "foo.bar", result.tool_calls_made.first[:name]
    assert_equal "foo_bar", result.tool_calls_made.first[:executed_name]

    tool_result_msg = result.messages.find(&:tool_result?)
    assert_equal "ok", tool_result_msg.content
  end

  def test_max_tool_calls_per_turn_trims_and_records_ignored_calls
    tool_call1 = AgentCore::ToolCall.new(id: "tc_1", name: "a", arguments: {})
    tool_call2 = AgentCore::ToolCall.new(id: "tc_2", name: "b", arguments: {})
    assistant_with_tools =
      AgentCore::Message.new(
        role: :assistant,
        content: "Calling tools",
        tool_calls: [tool_call1, tool_call2]
      )
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tools, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    executed = []
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "a", description: "A", parameters: {}) do |_args, **|
        executed << :a
        AgentCore::Resources::Tools::ToolResult.success(text: "a_ok")
      end
    )
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "b", description: "B", parameters: {}) do |_args, **|
        executed << :b
        AgentCore::Resources::Tools::ToolResult.success(text: "b_ok")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result =
      @runner.run(
        prompt: prompt, provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        max_tool_calls_per_turn: 1
      )

    assert_equal [:a], executed
    assert_equal 2, result.tool_calls_made.size
    assert_equal "b", result.tool_calls_made.first[:name]
    assert_includes result.tool_calls_made.first[:error], "ignored: max_tool_calls_per_turn=1"

    assistant_msg = result.messages.find { |m| m.assistant? && m.has_tool_calls? }
    assert assistant_msg
    assert_equal ["a"], assistant_msg.tool_calls.map(&:name)
  end

  def test_fix_empty_final_retries_without_tools
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    empty_final_msg = AgentCore::Message.new(role: :assistant, content: "")
    empty_final_response = AgentCore::Resources::Provider::Response.new(message: empty_final_msg, stop_reason: :end_turn)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Final answer")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, empty_final_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text", ""))
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    assert_equal "Final answer", result.text
    assert_equal 3, provider.calls.size
    assert_nil provider.calls[2][:tools]
    assert_equal "Please provide your final answer.", provider.calls[2][:messages].last.text

    fixup_msg = result.messages.find { |m| m.user? && m.text == "Please provide your final answer." }
    assert fixup_msg
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
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    assert_equal "Recovered", result.text
    assert_equal 1, result.tool_calls_made.size
    assert_match(/Tool not found:/, result.tool_calls_made.first[:error])
  end

  def test_max_turns_limit
    # Provider always returns tool calls — will hit max turns
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "loop" })
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
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
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

  def test_instrumentation_emits_run_turn_llm_and_tool_events
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 2)
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, usage: tool_usage, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Final answer")
    final_usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 6, output_tokens: 4)
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, usage: final_usage, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text", ""))
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    recorder = AgentCore::Observability::TraceRecorder.new(capture: :full)

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, instrumenter: recorder)
    assert_equal "Final answer", result.text

    names = recorder.trace.map { |e| e.fetch(:name) }
    assert_includes names, "agent_core.run"
    assert_includes names, "agent_core.turn"
    assert_includes names, "agent_core.llm.call"
    assert_includes names, "agent_core.tool.authorize"
    assert_includes names, "agent_core.tool.execute"

    run_evt = recorder.trace.find { |e| e.fetch(:name) == "agent_core.run" }
    assert run_evt

    run_payload = run_evt.fetch(:payload)
    assert run_payload.key?("run_id")
    assert run_payload.key?("duration_ms")
    assert_equal 2, run_payload.fetch("turns")
    assert_equal "end_turn", run_payload.fetch("stop_reason")
    assert run_payload.fetch("usage").is_a?(Hash)
    assert_equal 22, run_payload.fetch("usage").fetch("total_tokens")

    turn_evt = recorder.trace.find { |e| e.fetch(:name) == "agent_core.turn" }
    assert turn_evt

    turn_payload = turn_evt.fetch(:payload)
    assert turn_payload.key?("stop_reason")
    assert turn_payload.key?("turn_number")
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
      AgentCore::Resources::Tools::Tool.new(name: "dangerous", description: "bad", parameters: {}) do |_args, **|
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

  def test_tool_policy_confirm_pauses_and_resume_executes_tool
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "dangerous", arguments: { "x" => 1 })
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done.")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    executed = []
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "dangerous", description: "bad", parameters: {}) do |_args, **|
        executed << true
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    confirm_policy = Class.new(AgentCore::Resources::Tools::Policy::Base) do
      def authorize(name:, arguments: {}, context: {})
        AgentCore::Resources::Tools::Policy::Decision.confirm(reason: "need approval")
      end
    end.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "do something dangerous")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    recorder = AgentCore::Observability::TraceRecorder.new(capture: :full)

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: confirm_policy, instrumenter: recorder)

    assert result.awaiting_tool_confirmation?
    assert_instance_of AgentCore::PromptRunner::Continuation, result.continuation
    assert_equal 1, provider.calls.size
    assert_equal 0, executed.size

    pending = result.pending_tool_confirmations
    assert_equal 1, pending.size
    assert_equal "tc_1", pending.first.tool_call_id
    assert_equal "dangerous", pending.first.name

    resumed =
      @runner.resume(
        continuation: result.continuation,
        tool_confirmations: { "tc_1" => :allow },
        provider: provider,
        tools_registry: registry,
        tool_policy: confirm_policy,
        instrumenter: recorder
      )

    assert_equal "Done.", resumed.text
    assert_equal result.run_id, resumed.run_id
    assert_equal 2, provider.calls.size
    assert_equal 1, executed.size

    confirm_events =
      recorder.trace.select { |e|
        e.fetch(:name) == "agent_core.tool.authorize" &&
          e.fetch(:payload).fetch("stage", nil) == "confirmation"
      }
    assert_equal 1, confirm_events.size
    assert_equal "allow", confirm_events.first.fetch(:payload).fetch("outcome")
  end

  def test_resume_after_confirm_with_defer_includes_denied_tool_result_and_pauses
    tool_call_1 = AgentCore::ToolCall.new(id: "tc_1", name: "dangerous", arguments: { "x" => 1 })
    tool_call_2 = AgentCore::ToolCall.new(id: "tc_2", name: "echo", arguments: { "text" => "hi" })
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tools", tool_calls: [tool_call_1, tool_call_2])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, stop_reason: :tool_use)

    provider = MockProvider.new(responses: [tool_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "dangerous", description: "bad", parameters: {}) do |_args, **|
        raise "should not execute"
      end
    )
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute"
      end
    )

    confirm_policy = Class.new(AgentCore::Resources::Tools::Policy::Base) do
      def authorize(name:, arguments: {}, context: {})
        AgentCore::Resources::Tools::Policy::Decision.confirm(reason: "need approval")
      end
    end.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "do something")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: confirm_policy)

    assert paused.awaiting_tool_confirmation?
    assert_equal 1, provider.calls.size

    resumed =
      @runner.resume(
        continuation: paused.continuation,
        tool_confirmations: { "tc_1" => :deny, "tc_2" => :allow },
        provider: provider,
        tools_registry: registry,
        tool_policy: confirm_policy,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      )

    assert resumed.awaiting_tool_results?
    assert_equal 1, resumed.pending_tool_executions.size
    assert_equal "tc_2", resumed.pending_tool_executions.first.tool_call_id
    assert_equal 1, provider.calls.size

    tool_result_msgs = resumed.messages.select(&:tool_result?)
    assert_equal 1, tool_result_msgs.size
    assert_equal "tc_1", tool_result_msgs.first.tool_call_id
    assert_includes tool_result_msgs.first.text, "denied"
  end

  def test_streaming_confirm_emits_authorization_required_and_stops
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "dangerous", arguments: {})
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, stop_reason: :tool_use)

    provider = MockProvider.new(responses: [tool_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "dangerous", description: "bad", parameters: {}) do |_args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    confirm_policy = Class.new(AgentCore::Resources::Tools::Policy::Base) do
      def authorize(name:, arguments: {}, context: {})
        AgentCore::Resources::Tools::Policy::Decision.confirm(reason: "need approval")
      end
    end.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "do something dangerous")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    events_received = []
    result = @runner.run_stream(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: confirm_policy) do |event|
      events_received << event
    end

    assert result.awaiting_tool_confirmation?
    event_types = events_received.map(&:type)
    assert_includes event_types, :authorization_required
    refute_includes event_types, :tool_execution_start
    done_events = events_received.select { |e| e.type == :done }
    assert_equal 1, done_events.size
    assert_equal :awaiting_tool_confirmation, done_events.first.stop_reason
  end

  def test_streaming_deferred_tool_execution_emits_tool_execution_required_and_stops
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, stop_reason: :tool_use)

    provider = MockProvider.new(responses: [tool_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    events_received = []
    result =
      @runner.run_stream(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      ) do |event|
        events_received << event
      end

    assert result.awaiting_tool_results?
    event_types = events_received.map(&:type)
    assert_includes event_types, :tool_execution_required
    refute_includes event_types, :tool_execution_start
    done_events = events_received.select { |e| e.type == :done }
    assert_equal 1, done_events.size
    assert_equal :awaiting_tool_results, done_events.first.stop_reason
  end

  def test_resume_stream_with_tool_results_continues_and_streams_final
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Final answer")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused_events = []
    paused =
      @runner.run_stream(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      ) do |event|
        paused_events << event
      end

    assert paused.awaiting_tool_results?
    assert_includes paused_events.map(&:type), :tool_execution_required
    assert_equal 1, provider.calls.size

    resumed_events = []
    resumed =
      @runner.resume_stream_with_tool_results(
        continuation: paused.continuation,
        tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") },
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
      ) do |event|
        resumed_events << event
      end

    assert_equal "Final answer", resumed.text
    assert_equal paused.run_id, resumed.run_id
    assert_equal 2, provider.calls.size

    types = resumed_events.map(&:type)
    assert_includes types, :tool_execution_start
    assert_includes types, :tool_execution_end
    assert_includes types, :text_delta
    assert_includes types, :done
  end

  def test_resume_stream_after_confirm_executes_tool_and_streams_final
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "dangerous", arguments: { "x" => 1 })
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 5, output_tokens: 1)
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, usage: tool_usage, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done.")
    final_usage = AgentCore::Resources::Provider::Usage.new(input_tokens: 3, output_tokens: 2)
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, usage: final_usage, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    executed = []
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "dangerous", description: "bad", parameters: {}) do |_args, **|
        executed << true
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    confirm_policy = Class.new(AgentCore::Resources::Tools::Policy::Base) do
      def authorize(name:, arguments: {}, context: {})
        AgentCore::Resources::Tools::Policy::Decision.confirm(reason: "need approval")
      end
    end.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "do something dangerous")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    run_events = []
    paused = @runner.run_stream(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: confirm_policy) do |event|
      run_events << event
    end

    assert paused.awaiting_tool_confirmation?
    assert_equal 0, executed.size

    resume_events = []
    resumed =
      @runner.resume_stream(
        continuation: paused.continuation,
        tool_confirmations: { "tc_1" => :allow },
        provider: provider,
        tools_registry: registry,
        tool_policy: confirm_policy
      ) do |event|
        resume_events << event
      end

    assert_equal "Done.", resumed.text
    assert_equal paused.run_id, resumed.run_id
    assert_equal 1, executed.size
    assert_equal 2, provider.calls.size

    types = resume_events.map(&:type)
    assert_includes types, :tool_execution_start
    assert_includes types, :tool_execution_end
    assert_includes types, :text_delta
    assert_includes types, :done
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

  def test_streaming_run_with_tool_calling_emits_single_done
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Final answer")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text", ""))
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    events_received = []
    result = @runner.run_stream(prompt: prompt, provider: provider, tools_registry: registry) do |event|
      events_received << event
    end

    assert_equal "Final answer", result.text

    event_types = events_received.map(&:type)
    assert_includes event_types, :tool_execution_start
    assert_includes event_types, :tool_execution_end
    assert_includes event_types, :turn_end

    done_events = events_received.select { |e| e.type == :done }
    assert_equal 1, done_events.size
    assert_equal :end_turn, done_events.first.stop_reason
  end

  def test_streaming_fix_empty_final_retries_without_tools
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    empty_final_msg = AgentCore::Message.new(role: :assistant, content: "")
    empty_final_response = AgentCore::Resources::Provider::Response.new(message: empty_final_msg, stop_reason: :end_turn)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Final answer")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, empty_final_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text", ""))
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run_stream(prompt: prompt, provider: provider, tools_registry: registry) { }

    assert_equal "Final answer", result.text
    assert_equal 3, provider.calls.size
    assert_nil provider.calls[2][:tools]
    assert_equal "Please provide your final answer.", provider.calls[2][:messages].last.text
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
    assert_equal err.estimated_tokens, err.message_tokens + err.tool_tokens
    assert_equal 10, err.context_window
    assert_equal 0, err.tool_tokens
    assert_equal 10, err.limit
    # Provider should NOT have been called
    assert_equal 0, provider.calls.size
  end

  def test_preflight_emits_error_event_before_raising
    counter = AgentCore::Resources::TokenCounter::Heuristic.new
    provider = MockProvider.new
    events = AgentCore::PromptRunner::Events.new

    errors = []
    events.on_error { |e, recoverable| errors << [e.class, recoverable] }

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are a helpful assistant.",
      messages: [AgentCore::Message.new(role: :user, content: "Hello " * 100)],
      options: { model: "test" }
    )

    assert_raises(AgentCore::ContextWindowExceededError) do
      @runner.run(
        prompt: prompt, provider: provider, events: events,
        token_counter: counter, context_window: 10, reserved_output_tokens: 0
      )
    end

    assert_equal [[AgentCore::ContextWindowExceededError, false]], errors
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

    events_received = []
    assert_raises(AgentCore::ContextWindowExceededError) do
      @runner.run_stream(
        prompt: prompt, provider: provider,
        token_counter: counter, context_window: 50, reserved_output_tokens: 0
      ) { |event| events_received << event }
    end

    event_types = events_received.map(&:type)
    assert_includes event_types, :turn_start
    assert_includes event_types, :error
    assert_equal 0, provider.calls.size
  end

  # --- Multimodal tool results ---

  def test_tool_result_with_image_preserves_content_blocks
    # First response: assistant calls a screenshot tool
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "screenshot", arguments: {})
    assistant_with_tool = AgentCore::Message.new(
      role: :assistant, content: "Taking a screenshot.",
      tool_calls: [tool_call]
    )
    tool_response = AgentCore::Resources::Provider::Response.new(
      message: assistant_with_tool,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 5),
      stop_reason: :tool_use
    )

    # Second response: final text
    final_msg = AgentCore::Message.new(role: :assistant, content: "I can see the page.")
    final_response = AgentCore::Resources::Provider::Response.new(
      message: final_msg,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 20, output_tokens: 10),
      stop_reason: :end_turn
    )

    provider = MockProvider.new(responses: [tool_response, final_response])

    # Register a tool that returns text + image
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "screenshot", description: "Take screenshot", parameters: {}) do |_args, **|
        AgentCore::Resources::Tools::ToolResult.with_content([
          { type: "text", text: "Screenshot captured" },
          { type: "image", source_type: "base64", media_type: "image/png", data: "iVBOR" },
        ])
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are helpful.",
      messages: [AgentCore::Message.new(role: :user, content: "Take a screenshot")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    # Find the tool_result message in the conversation
    tool_result_msg = result.messages.find { |m| m.tool_result? }
    assert tool_result_msg, "Expected a tool_result message"

    # Content should be an array of ContentBlock objects, not a plain string
    assert_kind_of Array, tool_result_msg.content
    assert_equal 2, tool_result_msg.content.size
    assert_instance_of AgentCore::TextContent, tool_result_msg.content[0]
    assert_instance_of AgentCore::ImageContent, tool_result_msg.content[1]
    assert_equal :base64, tool_result_msg.content[1].source_type
    assert_equal "image/png", tool_result_msg.content[1].media_type
  end

  def test_tool_result_text_only_stays_as_string
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_with_tool = AgentCore::Message.new(
      role: :assistant, content: "Echoing.",
      tool_calls: [tool_call]
    )
    tool_response = AgentCore::Resources::Provider::Response.new(
      message: assistant_with_tool,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 5),
      stop_reason: :tool_use
    )

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(
      message: final_msg,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 15, output_tokens: 5),
      stop_reason: :end_turn
    )

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |args, **|
        AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text", ""))
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are helpful.",
      messages: [AgentCore::Message.new(role: :user, content: "Echo hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    tool_result_msg = result.messages.find { |m| m.tool_result? }
    assert tool_result_msg
    # Text-only results stay as simple strings (backward compatible)
    assert_kind_of String, tool_result_msg.content
    assert_equal "hi", tool_result_msg.content
  end

  def test_tool_result_invalid_multimodal_content_falls_back_to_text_error
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "screenshot", arguments: {})
    assistant_with_tool = AgentCore::Message.new(
      role: :assistant, content: "Taking a screenshot.",
      tool_calls: [tool_call]
    )
    tool_response = AgentCore::Resources::Provider::Response.new(
      message: assistant_with_tool,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 5),
      stop_reason: :tool_use
    )

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(
      message: final_msg,
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 15, output_tokens: 5),
      stop_reason: :end_turn
    )

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "screenshot", description: "Take screenshot", parameters: {}) do |_args, **|
        AgentCore::Resources::Tools::ToolResult.with_content([
          { type: "text", text: "Screenshot captured" },
          # Invalid: base64 image missing media_type triggers ImageContent validation error
          { type: "image", source_type: "base64", data: "iVBOR" },
        ])
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "You are helpful.",
      messages: [AgentCore::Message.new(role: :user, content: "Take a screenshot")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    result = @runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: @allow_all)

    tool_result_msg = result.messages.find { |m| m.tool_result? }
    assert tool_result_msg
    assert_kind_of String, tool_result_msg.content
    assert_includes tool_result_msg.content, "invalid multimodal content"
    assert tool_result_msg.metadata[:error]
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
