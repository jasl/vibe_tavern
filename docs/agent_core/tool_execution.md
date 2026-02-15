# Tool execution (AgentCore vNext)

By default, AgentCore executes tools **synchronously** and **inline** on the
runner thread. This is simple, but it means long-running tools will block the
agent loop.

AgentCore vNext introduces a pluggable `ToolExecutor` so apps can choose the
best execution strategy:

- `Inline` (default): synchronous, deterministic
- `DeferAll`: pause and let the app execute tools out-of-band (ActiveJob/MQ/etc.)
- `ThreadPool`: same-turn parallel execution (opt-in per tool)

## Inline (default)

No extra configuration:

```ruby
runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: policy)
```

## Defer execution (pause/resume)

Use `ToolExecutor::DeferAll` to **pause** the run when the LLM produces tool
calls, instead of executing any tool immediately.

```ruby
runner = AgentCore::PromptRunner::Runner.new

result =
  runner.run(
    prompt: prompt,
    provider: provider,
    tools_registry: registry,
    tool_policy: policy,
    tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
  )

if result.awaiting_tool_results?
  pending = result.pending_tool_executions
  # => [PendingToolExecution(tool_call_id:, name:, executed_name:, arguments:, arguments_summary:, source:), ...]
end
```

When paused:

- `stop_reason` is `:awaiting_tool_results`
- no tool is executed by AgentCore
- the app executes tools and then resumes by calling:
  - `Runner#resume_with_tool_results` (sync)
  - `Runner#resume_stream_with_tool_results` (streaming)

### Resume (sync)

```ruby
tool_results = {
  "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok"),
}

result =
  runner.resume_with_tool_results(
    continuation: result.continuation,
    tool_results: tool_results, # tool_call_id => ToolResult (ToolResult only)
    provider: provider,
    tools_registry: registry,
    tool_policy: policy,
  )
```

### Rails ActiveJob example (offload tool execution)

AgentCore does not prescribe persistence; one workable Rails pattern is:

1. Persist `continuation` keyed by `run_id`.
2. Enqueue one job per `PendingToolExecution`.
3. Persist `ToolResult` output keyed by `run_id` + `tool_call_id`.
4. When all tool results are ready, resume the run.

Example sketch (adapt to your persistence choices):

```ruby
# app/jobs/execute_tool_call_job.rb
class ExecuteToolCallJob < ApplicationJob
  queue_as :default

  def perform(run_id:, tool_call_id:, name:, arguments:)
    registry = AppTools.registry
    ctx = AgentCore::ExecutionContext.from({ run_id: run_id, user_id: Current.user&.id })

    result = registry.execute(name: name, arguments: arguments, context: ctx)

    ToolResultRecord.create!(
      run_id: run_id,
      tool_call_id: tool_call_id,
      tool_result: result.to_h, # app-defined serialization
    )
  end
end

# Somewhere in your controller/service when you get awaiting_tool_results:
run_id = result.run_id
ContinuationRecord.create!(run_id: run_id, payload: Marshal.dump(result.continuation))

result.pending_tool_executions.each do |p|
  ExecuteToolCallJob.perform_later(
    run_id: run_id,
    tool_call_id: p.tool_call_id,
    name: p.executed_name,
    arguments: p.arguments,
  )
end

# Later, when all results are ready (polling or callback):
continuation = Marshal.load(ContinuationRecord.find_by!(run_id: run_id).payload)

tool_results =
  ToolResultRecord.where(run_id: run_id).to_h do |r|
    h = AgentCore::Utils.symbolize_keys(r.tool_result)
    [
      r.tool_call_id,
      AgentCore::Resources::Tools::ToolResult.new(
        content: h.fetch(:content),
        error: h.fetch(:error, false),
        metadata: h.fetch(:metadata, {}),
      ),
    ]
  end

runner = AgentCore::PromptRunner::Runner.new
runner.resume_with_tool_results(
  continuation: continuation,
  tool_results: tool_results,
  provider: provider,
  tools_registry: AppTools.registry,
  tool_policy: AppTools.policy,
)
```

Notes:

- `continuation` is intended to be treated as **opaque**. If you persist it, you
  own the serialization format and upgrade path.
- `resume_with_tool_results` only accepts `ToolResult` values (no Hash/String
  coercion).

## Same-turn parallel execution (ThreadPool)

Use `ToolExecutor::ThreadPool` to run *some* tools concurrently within the same
turn. To avoid thread-safety surprises, parallelism is **explicit opt-in**:

- only tools with `Tool.metadata[:parallelizable] == true` are parallelized
- all other tools still run sequentially
- results (and streaming events) are emitted in the original tool_call order

```ruby
executor = AgentCore::PromptRunner::ToolExecutor::ThreadPool.new(max_concurrency: 4)

runner.run(
  prompt: prompt,
  provider: provider,
  tools_registry: registry,
  tool_policy: policy,
  tool_executor: executor,
)
```

MCP tools are not parallel by default. If you want parallel MCP calls, prefer an
app-side native tool wrapper that manages its own concurrency guarantees.

## Related: tool authorization vs execution defer

Tool authorization (`Decision.confirm(...)` pause/resume) and deferred execution
(`:awaiting_tool_results` pause/resume) are independent mechanisms and can be
composed:

- first pause for confirmation (`:awaiting_tool_confirmation`)
- after approval, resume; if your executor is `DeferAll`, the run may then pause
  again for external tool execution (`:awaiting_tool_results`)

See also: `docs/agent_core/tool_authorization.md`.
