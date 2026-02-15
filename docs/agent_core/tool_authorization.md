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
- `authorize(name:, arguments:, context:)` — per-tool-call decision

Decisions are:

- `Decision.allow(reason: nil)`
- `Decision.deny(reason:)`
- `Decision.confirm(reason:)` (pause)

`context` is an `AgentCore::ExecutionContext` (contains `run_id` and app-provided
`attributes`).

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

## Suggested app pattern

In an app/UI, treat `pending_tool_confirmations` as an **authorization request**
record:

- present `name`, `arguments_summary`, and `reason` to the user/admin
- store an approval decision keyed by `tool_call_id`
- call `resume`/`resume_stream` with those decisions

If you need persistence across process restarts, explicitly serialize the
continuation state in your app (AgentCore does not guarantee JSON compatibility
for arbitrary embedded values by default).

