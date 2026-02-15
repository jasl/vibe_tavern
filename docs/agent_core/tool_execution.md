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

### Partial resume (optional)

By default, `resume_with_tool_results` requires results for all pending tool
calls. If you receive results incrementally, pass `allow_partial: true` to
buffer results and keep the run paused until all tool results are available:

```ruby
result =
  runner.resume_with_tool_results(
    continuation: result.continuation,
    tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") },
    provider: provider,
    tools_registry: registry,
    tool_policy: policy,
    allow_partial: true,
  )
```

## Task payloads (ToolTaskCodec)

For app-side schedulers (ActiveJob/MQ/worker processes), you can derive a
stable JSON-safe task payload from a continuation:

```ruby
payload =
  AgentCore::PromptRunner::ToolTaskCodec.dump(
    result.continuation,
    context_keys: %i[tenant_id user_id workspace_id session_id],
  )

payload.fetch("tasks").each do |t|
  ExecuteToolCallJob.perform_later(
    run_id: payload.fetch("run_id"),
    tool_call_id: t.fetch("tool_call_id"),
    name: t.fetch("executed_name"),
    arguments: t.fetch("arguments"),
  )
end
```

Notes:

- Tool task payloads include **raw tool arguments**. Treat them as sensitive:
  avoid untrusted logs and use appropriate at-rest protections.
- `context_keys:` is an explicit allowlist. Keep it minimal (IDs only).

## Using Agent / AgentSession (recommended entrypoints)

### Agent (gem)

```ruby
agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.model = "m1"
  b.system_prompt = "You can use tools."
  b.tools_registry = registry
  b.tool_policy = policy
  b.tool_executor = AgentCore::PromptRunner::ToolExecutor::DeferAll.new
end

paused = agent.chat("hi")

if paused.awaiting_tool_results?
  tool_results = { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") }
  final = agent.resume_with_tool_results(continuation: paused, tool_results: tool_results, allow_partial: true)
end
```

### AgentSession (app contrib)

```ruby
session =
  AgentCore::Contrib::AgentSession.new(
    provider: provider,
    model: "m1",
    system_prompt: "",
    history: [],
    tools_registry: registry,
    tool_policy: policy,
    tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
  )

paused = session.chat("hi")

if paused.awaiting_tool_results?
  tool_results = { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") }
  final = session.resume_with_tool_results(continuation: paused, tool_results: tool_results, allow_partial: true)
end
```

### Rails ActiveJob example (offload tool execution)

AgentCore does not prescribe persistence; one workable Rails pattern is:

1. Persist `continuation` keyed by `(run_id, continuation_id)`.
2. Enqueue one job per `PendingToolExecution`.
3. Persist `ToolResult` output keyed by `(run_id, continuation_id, tool_call_id)`.
4. When all tool results are ready, resume the run (or use `allow_partial: true` to resume incrementally).

Example sketch (adapt to your persistence choices):

```ruby
# app/jobs/execute_tool_call_job.rb
class ExecuteToolCallJob < ApplicationJob
  queue_as :default

  def perform(run_id:, tool_call_id:, name:, arguments:)
    registry = AppTools.registry
    ctx = AgentCore::ExecutionContext.from({ user_id: Current.user&.id }).with(run_id: run_id)

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

payload =
  AgentCore::PromptRunner::ContinuationCodec.dump(
    result.continuation,
    # Only persist explicitly allowlisted context attributes.
    # Keep this minimal (avoid secrets) — it may be stored long-term.
    context_keys: %i[tenant_id user_id workspace_id session_id],
    include_traces: true,
  )

ContinuationRecord.create!(
  run_id: run_id,
  continuation_id: payload.fetch("continuation_id"),
  parent_continuation_id: payload.fetch("parent_continuation_id", nil),
  status: "current", # app-defined; supports optimistic locking / single-consume
  payload: payload,  # jsonb
)

result.pending_tool_executions.each do |p|
  ExecuteToolCallJob.perform_later(
    run_id: run_id,
    continuation_id: payload.fetch("continuation_id"),
    tool_call_id: p.tool_call_id,
    name: p.executed_name,
    arguments: p.arguments,
  )
end

# Later, when all results are ready (polling or callback):
continuation_payload = ContinuationRecord.find_by!(run_id: run_id, status: "current").payload
continuation = AgentCore::PromptRunner::ContinuationCodec.load(continuation_payload)

tool_results =
  ToolResultRecord.where(run_id: run_id, continuation_id: continuation_payload.fetch("continuation_id")).to_h do |r|
    [
      r.tool_call_id,
      AgentCore::Resources::Tools::ToolResult.from_h(r.tool_result),
    ]
  end

runner = AgentCore::PromptRunner::Runner.new
runner.resume_with_tool_results(
  # Runner also accepts the JSON payload Hash/String directly.
  continuation: continuation,
  tool_results: tool_results,
  provider: provider,
  tools_registry: AppTools.registry,
  tool_policy: AppTools.policy,
)
```

Notes:

- `continuation` is intended to be treated as **opaque**. For stable
  persistence, use `ContinuationCodec` (versioned, JSON-safe).
- Each pause generates a new `continuation_id`. Apps should treat continuations
  as single-use tokens and implement optimistic locking / CAS so stale
  continuations cannot be resumed concurrently.
- If `ContinuationCodec` rejects an old/new payload (`schema_version` mismatch),
  you must decide on an app-level migration or fail the resume attempt.
- `resume_with_tool_results` only accepts `ToolResult` values (no Hash/String
  coercion). Use `ToolResult.from_h(...)` for persisted Hash/JSON payloads.

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
