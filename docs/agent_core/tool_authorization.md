# Tool authorization (AgentCore vNext)

AgentCore supports **policy-driven tool authorization** with a production-ready
confirmation flow:

- tools are **deny-by-default** (unless you explicitly provide a policy)
- a policy can return `confirm`, which **pauses** the run (no tool executes)
- the app can **resume** later with user/admin approvals

This enables product needs like:

- user authorization for tool actions (filesystem, network, MCP, skills)
- audit logs for “who approved what, when”
- predictable billing (LLM calls vs tool calls)

## Policy API

A tool policy implements:

- `filter(tools:, context:)` — which tools are visible to the LLM
- `authorize(name:, arguments:, context:)` — per-tool-call decision (**name is the executed tool name**, resolved against the registry)

Decisions are:

- `Decision.allow(reason: nil)`
- `Decision.deny(reason:)`
- `Decision.confirm(reason:)` (pause)

`context` is an `AgentCore::ExecutionContext` (contains `run_id` and app-provided
`attributes`).

Notes:

- The runner resolves the assistant-requested tool name against the registry
  (including a `.` → `_` fallback) and passes the resolved **executed name** to
  `authorize(name:)`. This prevents aliasing from bypassing policy checks.
- `PendingToolConfirmation#name` is the assistant-requested name (for UI
  display). For audit/debugging, prefer using `tool_calls_made` (requested +
  executed) and observability payloads which include `executed_name`.

## Runner pause/resume

### Synchronous

```ruby
runner = AgentCore::PromptRunner::Runner.new

result =
  runner.run(
    prompt: prompt,
    provider: provider,
    tools_registry: registry,
    tool_policy: policy,
    context: { user_id: current_user.id },
  )

if result.awaiting_tool_confirmation?
  pending = result.pending_tool_confirmations
  # => [PendingToolConfirmation(tool_call_id:, name:, arguments:, reason:, arguments_summary:), ...]

  confirmations =
    pending.to_h do |p|
      [p.tool_call_id, :deny] # or :allow
    end

  result =
    runner.resume(
      continuation: result.continuation,
      tool_confirmations: confirmations, # tool_call_id => :allow/:deny (or true/false)
      provider: provider,
      tools_registry: registry,
      tool_policy: policy,
      context: { user_id: current_user.id }, # optional; defaults to continuation.context_attributes
    )
end
```

Notes:

- When paused, AgentCore does **not** execute any tool calls.
- `run_id` is stable across `run` and `resume` (useful for correlating audits).
- The `continuation` object is intended to be treated as **opaque**.
- Tool authorization pause/resume is independent from tool execution pause/resume
  (defer execution to the app). They can be composed (confirm first, then defer).
  See `docs/agent_core/tool_execution.md`.

### Streaming

`run_stream` may emit `AgentCore::StreamEvent::AuthorizationRequired` when a
confirmation decision occurs. Your UI can stop streaming and prompt for approval,
then resume:

```ruby
result =
  runner.run_stream(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: policy) do |event|
    case event
    when AgentCore::StreamEvent::AuthorizationRequired
      # event.pending_tool_confirmations
    end
  end

if result.awaiting_tool_confirmation?
  runner.resume_stream(
    continuation: result.continuation,
    tool_confirmations: { "tc_1" => :allow },
    provider: provider,
    tools_registry: registry,
    tool_policy: policy,
  ) { |event| ... }
end
```

## Using Agent / AgentSession (recommended entrypoints)

### Agent (gem)

`AgentCore::Agent` exposes top-level pause/resume helpers so app code does not
need to call `PromptRunner::Runner#resume` directly:

```ruby
agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.model = "m1"
  b.system_prompt = "You can use tools."
  b.tools_registry = registry
  b.tool_policy = policy
end

paused = agent.chat("do something")

if paused.awaiting_tool_confirmation?
  final = agent.resume(continuation: paused, tool_confirmations: { "tc_1" => :allow })
end
```

`continuation:` accepts either a `PromptRunner::Continuation` or a `RunResult`
(Agent will use `run_result.continuation`).

### AgentSession (app contrib)

In this repo, prefer `AgentCore::Contrib::AgentSession` as the UI/session-level
entrypoint:

```ruby
session =
  AgentCore::Contrib::AgentSession.new(
    provider: provider,
    model: "m1",
    system_prompt: "",
    history: [],
    tools_registry: registry,
    tool_policy: policy,
  )

paused = session.chat("do something")

if paused.awaiting_tool_confirmation?
  final = session.resume(continuation: paused, tool_confirmations: { "tc_1" => :allow })
end
```

## Suggested app pattern

In an app/UI, treat `pending_tool_confirmations` as an **authorization request**
record:

- present `name`, `arguments_summary`, and `reason` to the user/admin
- store an approval decision keyed by `tool_call_id`
- call `resume`/`resume_stream` with those decisions

If you need persistence across process restarts, explicitly serialize the
continuation state in your app. Recommended: use
`AgentCore::PromptRunner::ContinuationCodec` (versioned, JSON-safe) and only
persist explicitly allowlisted context attributes (`context_keys:`).

## Auditing confirmation decisions

`Decision.confirm(...)` intentionally moves the final authorization decision
into your app/UI. Recommended place to record audits is the moment the user (or
admin) approves/denies:

- `run_id` (from `RunResult.run_id` / `RunResult.continuation.run_id`)
- `tool_call_id`
- decision (`allow` / `deny`)
- actor (`user_id`, admin ID), timestamp, and any justification

If you want everything in a single observability backend, you can publish an
app-side event at approval time (example schema; you own it):

```ruby
instrumenter.publish(
  "agent_core.tool.confirmation",
  {
    run_id: run_id,
    tool_call_id: tool_call_id,
    outcome: "allow",
    actor_id: current_user.id,
  }
)
```

AgentCore also publishes `agent_core.tool.authorize` with `stage: "confirmation"`
when you call `resume`/`resume_stream`, but this happens at resume time (not at
the exact moment the user clicked approve/deny).

## Example: app-side authorization flow (in-memory)

This example shows a complete, app-controlled pause/resume loop with:

- a simple tool policy that returns `confirm` for risky tools
- an in-memory continuation store keyed by `run_id`
- a separate audit record published at approval time

```ruby
class AppToolPolicy < AgentCore::Resources::Tools::Policy::Base
  RISKY_TOOLS = %w[skills.read_file filesystem.write mcp.shell].freeze

  def filter(tools:, context:)
    # Tool visibility and tool execution are separate checks.
    # In production you likely want an allowlist here.
    tools
  end

  def authorize(name:, arguments:, context:)
    user_id = context.attributes[:user_id]
    return Decision.deny(reason: "unauthenticated") unless user_id

    if RISKY_TOOLS.include?(name.to_s)
      Decision.confirm(reason: "requires user approval")
    else
      Decision.allow
    end
  end
end

class ContinuationStore
  def initialize
    @mutex = Mutex.new
    @by_run_id = {}
  end

  def write(run_id, continuation)
    @mutex.synchronize { @by_run_id[run_id.to_s] = continuation }
  end

  def read(run_id)
    @mutex.synchronize { @by_run_id.fetch(run_id.to_s) }
  end
end

store = ContinuationStore.new
policy = AppToolPolicy.new

result = runner.run(prompt: prompt, provider: provider, tools_registry: registry, tool_policy: policy, context: { user_id: 123 })

if result.awaiting_tool_confirmation?
  store.write(result.run_id, result.continuation)
  # Show result.pending_tool_confirmations in your UI and collect allow/deny decisions.
end

# Later, after user approves/denies in the UI:
continuation = store.read(run_id)
confirmations = { "tc_1" => :allow, "tc_2" => :deny } # tool_call_id => :allow/:deny

instrumenter.publish(
  "agent_core.tool.confirmation",
  { run_id: run_id, decisions: confirmations, actor_id: 123 }
)

result =
  runner.resume(
    continuation: continuation,
    tool_confirmations: confirmations,
    provider: provider,
    tools_registry: registry,
    tool_policy: policy,
    context: { user_id: 123 }
  )
```
