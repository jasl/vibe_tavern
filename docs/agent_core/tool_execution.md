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

AgentCore does not prescribe persistence, but this repo includes a minimal,
copy/paste-ready Rails pattern:

- Tables: `continuation_records` / `tool_result_records` (see
  `db/migrate/*_create_continuation_records.rb` and
  `db/migrate/*_create_tool_result_records.rb`)
- Models: `ContinuationRecord` / `ToolResultRecord` (CAS consume + idempotent
  upsert)
- Job: `LLM::ExecuteToolCallJob` (execute one tool call and store result)
- Services: `LLM::RunToolChat` / `LLM::ResumeToolChat` (pause/resume orchestration)

### CAS consume! (stale continuation protection)

```ruby
ContinuationRecord.consume!(run_id: run_id, continuation_id: continuation_id)
```

If the update affects 0 rows, `consume!` raises
`ContinuationRecord::StaleContinuationError` (another worker already resumed it
or it is not current).

### Start (pause + enqueue tasks)

`LLM::RunToolChat` runs the tool loop with `ToolExecutor::DeferAll`, persists
the continuation, derives `ToolTaskCodec` payloads, and enqueues
`LLM::ExecuteToolCallJob` jobs.

```ruby
started =
  LLM::RunToolChat.call(
    llm_model: llm_model,
    user_text: "hi",
    tooling_key: "default",
    context: { tenant_id: "t1" },
    context_keys: %i[tenant_id],
  )

run_id = started.value.fetch(:run_id)
continuation_id = started.value.fetch(:continuation_id) # present when paused
```

### Resume (consume + allow_partial)

`LLM::ResumeToolChat` consumes the checkpoint (`continuation_id`), loads the
continuation payload, gathers tool results, and resumes with
`allow_partial: true`. If it pauses again, it persists the next continuation and
enqueues any missing tool tasks.

```ruby
resumed =
  LLM::ResumeToolChat.call(
    run_id: run_id,
    continuation_id: continuation_id,
  )
```

Notes:

- `continuation` is intended to be treated as **opaque**. For stable
  persistence, use `ContinuationCodec` (versioned, JSON-safe).
- Each pause generates a new `continuation_id`. Apps should treat continuations
  as single-use tokens and implement optimistic locking / CAS so stale
  continuations cannot be resumed concurrently.
- If you use `allow_partial: true` and resume multiple times before all tools
  finish, `continuation_id` will rotate. Prefer keying tool results by
  `(run_id, tool_call_id)` to avoid losing results produced under an earlier
  checkpoint, or aggregate results across the `parent_continuation_id` chain.
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
