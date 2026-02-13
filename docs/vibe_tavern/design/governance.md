# Governance (tool policy + audit events)

This document describes the **control-plane hooks** exposed by
`TavernKit::VibeTavern` for production hosts (especially multi-tenant SaaS).

Scope:
- tool **authorization** (allow/deny/confirm)
- tool **exposure filtering** (reduce the tool list sent to the model)
- structured **events** for audit/logging pipelines

Non-goals:
- UI flows for confirmation/consent
- storage/retention/WORM implementations
- OAuth flows (MCP auth is injected by the host; see `design/mcp.md`)

## Tool policy hook

Configure via `context[:tool_calling]`:

```ruby
context[:tool_calling] = {
  policy: MyPolicy.new,                # optional
  policy_error_mode: :deny,            # :deny (default) | :allow | :raise
  event_context_keys: %i[tenant_id user_id trace_id], # optional, default []
}
```

### Interface

The policy object must respond to:

- `filter_tools(tools:, context:, expose:)`
  - called before each LLM request (when tools are enabled)
  - must return an Array of tool hashes
  - must return a **subset** of the provided tools (by tool name)
- `authorize_call(name:, args:, context:, tool_call_id:)`
  - called immediately before tool execution
  - must return a `Policies::Decision` (or a compatible Hash)

Code:
- `lib/tavern_kit/vibe_tavern/tool_calling/policies/tool_policy.rb`

### Decision outcomes

`authorize_call` returns a decision with `outcome`:

- `:allow`: execute the tool
- `:deny`: do not execute; tool result contains:
  - error code: `TOOL_POLICY_DENIED`
  - `data.policy`: `{ outcome, decision_id?, reason_codes[], message? }`
- `:confirm`: do not execute; tool result contains:
  - error code: `TOOL_CONFIRMATION_REQUIRED`
  - `data.policy`: `{ outcome, decision_id?, reason_codes[], message?, confirm: {...} }`

This lets the host implement human-in-the-loop confirmation without coupling it
to the infra layer.

### `policy_error_mode`

Policy failures are handled according to `policy_error_mode`:

- `:deny` (default, fail-closed)
  - exposure filtering errors result in an empty `tools:` list (no tools exposed)
  - authorization errors result in `TOOL_POLICY_ERROR` for that tool call
- `:allow` (fail-open)
  - ignores policy errors and continues
- `:raise` (fail-fast)
  - tool exposure/authorization errors fail the run with `ToolUseError` (`code: "POLICY_ERROR"`)

## ToolLoopRunner events (audit/log sink)

`ToolLoopRunner#run` accepts `on_event:` (or a block) to receive structured
events:

```ruby
events = []
runner.run(user_text: "...", on_event: ->(e) { events << e })
```

All events include:
- `type` (Symbol)
- `run_id` (UUID per `run`)
- `context_type` / `context_id` (from `RunnerConfig.context`)
- `context` (Hash) containing only the keys listed in `event_context_keys` (values are `to_s` and truncated)

Additional events introduced for governance:
- `:tools_filtered`
  - emitted when the policy removes tools from the model-visible tool list
- `:policy_error`
  - emitted when the policy raises/returns invalid data during exposure/call checks

Tool execution events:
- `:tool_call_end` includes lightweight summaries when available:
  - `policy: { outcome, decision_id, reason_codes }`
  - `mcp: { server_id, remote_tool_name }`

Code:
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`

## Host TODO (production)

The infra layer only emits the hooks and minimal envelopes. A production host
should additionally implement:

- Redaction: never log raw tool arguments/outputs or secrets in headers/env.
- Decision logs: store `{ decision_id, reason_codes, outcome }` with trace IDs.
- Confirmation UI: render `TOOL_CONFIRMATION_REQUIRED` confirmations and resume safely.
- Multi-tenant isolation: ensure `context` includes tenant/user/workspace identifiers and that runtime state never crosses tenants.

