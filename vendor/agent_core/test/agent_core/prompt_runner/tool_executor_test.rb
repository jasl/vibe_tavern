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
end
