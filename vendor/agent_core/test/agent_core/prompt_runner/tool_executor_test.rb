# frozen_string_literal: true

require "test_helper"
require "timeout"

class AgentCore::PromptRunner::ToolExecutorTest < Minitest::Test
  def test_thread_pool_executes_parallelizable_tools_concurrently
    registry = AgentCore::Resources::Tools::Registry.new

    started = Queue.new
    release = Queue.new

    handler =
      lambda do |_args, **|
        started << true
        release.pop
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end

    registry.register(
      AgentCore::Resources::Tools::Tool.new(
        name: "a",
        description: "A",
        parameters: {},
        metadata: { parallelizable: true },
        &handler
      )
    )

    registry.register(
      AgentCore::Resources::Tools::Tool.new(
        name: "b",
        description: "B",
        parameters: {},
        metadata: { parallelizable: true },
        &handler
      )
    )

    requests = [
      AgentCore::PromptRunner::ToolExecutor::ExecutionRequest.new(
        tool_call_id: "tc_1",
        name: "a",
        executed_name: "a",
        arguments: {},
        arguments_summary: "{}",
        source: "native",
      ),
      AgentCore::PromptRunner::ToolExecutor::ExecutionRequest.new(
        tool_call_id: "tc_2",
        name: "b",
        executed_name: "b",
        arguments: {},
        arguments_summary: "{}",
        source: "native",
      ),
    ]

    executor = AgentCore::PromptRunner::ToolExecutor::ThreadPool.new(max_concurrency: 2)
    execution_context = AgentCore::ExecutionContext.from(nil)

    exec_thread = Thread.new do
      executor.execute(
        requests: requests,
        tools_registry: registry,
        execution_context: execution_context,
        max_tool_output_bytes: 10_000,
      )
    end

    Timeout.timeout(1) { 2.times { started.pop } }
    2.times { release << true }

    result = exec_thread.value
    assert_equal 2, result.completed.size
    assert_equal [], result.deferred
  ensure
    2.times { release << true } if defined?(release) && release
    exec_thread&.kill if exec_thread&.alive?
  end

  def test_thread_pool_does_not_hang_when_worker_raises_exception
    registry = AgentCore::Resources::Tools::Registry.new

    boom = Class.new(Exception)

    registry.register(
      AgentCore::Resources::Tools::Tool.new(
        name: "boom",
        description: "Boom",
        parameters: {},
        metadata: { parallelizable: true },
      ) do |_args, **|
        raise boom, "nope"
      end
    )

    requests = [
      AgentCore::PromptRunner::ToolExecutor::ExecutionRequest.new(
        tool_call_id: "tc_1",
        name: "boom",
        executed_name: "boom",
        arguments: {},
        arguments_summary: "{}",
        source: "native",
      ),
    ]

    executor = AgentCore::PromptRunner::ToolExecutor::ThreadPool.new(max_concurrency: 1)
    execution_context = AgentCore::ExecutionContext.from(nil)

    Timeout.timeout(1) do
      assert_raises(boom) do
        executor.execute(
          requests: requests,
          tools_registry: registry,
          execution_context: execution_context,
          max_tool_output_bytes: 10_000,
        )
      end
    end
  end

  def test_inline_executor_standard_error_does_not_leak_exception_message_by_default
    registry = AgentCore::Resources::Tools::Registry.new

    registry.register(
      AgentCore::Resources::Tools::Tool.new(
        name: "boom",
        description: "Boom",
        parameters: {},
      ) do |_args, **|
        raise "SECRET"
      end
    )

    requests = [
      AgentCore::PromptRunner::ToolExecutor::ExecutionRequest.new(
        tool_call_id: "tc_1",
        name: "boom",
        executed_name: "boom",
        arguments: {},
        arguments_summary: "{}",
        source: "native",
      ),
    ]

    executor = AgentCore::PromptRunner::ToolExecutor::Inline.new
    execution_context = AgentCore::ExecutionContext.from(nil)

    result =
      executor.execute(
        requests: requests,
        tools_registry: registry,
        execution_context: execution_context,
        max_tool_output_bytes: 10_000,
      )

    tool_result = result.completed.first.result
    assert tool_result.error?
    refute_includes tool_result.text, "SECRET"

    debug_executor = AgentCore::PromptRunner::ToolExecutor::Inline.new(tool_error_mode: :debug)

    debug_result =
      debug_executor.execute(
        requests: requests,
        tools_registry: registry,
        execution_context: execution_context,
        max_tool_output_bytes: 10_000,
      )

    debug_tool_result = debug_result.completed.first.result
    assert debug_tool_result.error?
    assert_includes debug_tool_result.text, "SECRET"
  end
end
