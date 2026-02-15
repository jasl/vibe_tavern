# Observability (AgentCore)

AgentCore supports **structured observation** for production debugging, audit
logs, and billing. The core idea is an instrumenter interface that can publish
events to any sink (logs, ActiveSupport::Notifications, OpenTelemetry, etc.).

## Instrumentation interface

- `AgentCore::Observability::Instrumenter#instrument(name, payload = {}) { ... }`
  - measures `duration_ms` (monotonic)
  - captures `error` (class/message) if the block raises, then re-raises
  - calls `publish(name, payload)`
- Default: `AgentCore::Observability::NullInstrumenter` (no-op)

AgentCore calls the instrumenter for:

- run lifecycle
- each turn (one LLM call)
- each LLM call
- each tool authorization decision
- each tool execution (including denied/failed tool calls)

## Adapters (soft dependencies)

AgentCore ships optional adapters that integrate with common Ruby observability
backends. These are **soft dependencies** (you must `require` them explicitly).

### ActiveSupport::Notifications (Rails)

```ruby
require "agent_core"
require "agent_core/observability/adapters/active_support_notifications_instrumenter"

instrumenter =
  AgentCore::Observability::Adapters::ActiveSupportNotificationsInstrumenter.new
```

You can also inject a notifier object that responds to `#instrument`:

```ruby
instrumenter =
  AgentCore::Observability::Adapters::ActiveSupportNotificationsInstrumenter.new(
    notifier: ActiveSupport::Notifications
  )
```

### OpenTelemetry

```ruby
require "agent_core"
require "agent_core/observability/adapters/open_telemetry_instrumenter"

instrumenter =
  AgentCore::Observability::Adapters::OpenTelemetryInstrumenter.new
```

You can also inject a tracer object that responds to `#in_span` (useful for
custom tracer providers or tests).

## Event names (vNext)

Runner currently emits these events:

- `agent_core.run`
- `agent_core.turn`
- `agent_core.llm.call`
- `agent_core.tool.authorize`
- `agent_core.tool.execute`

All payloads include:

- `run_id` (stable across pause/resume)
- `duration_ms`

Typical payload fields:

- `agent_core.run`: `resumed` (when resuming), `stop_reason`, `turns`, `usage`
- `agent_core.turn`: `turn_number`, `stop_reason`, `usage`
- `agent_core.llm.call`: `model`, `stream`, `messages_count`, `tools_count`,
  `options_summary`, `stop_reason`, `usage`
- `agent_core.tool.authorize`: `tool_call_id`, `name`, `arguments_summary`,
  `outcome` (`allow|deny|confirm`), `reason`
- `agent_core.tool.execute`: `tool_call_id`, `name`, `executed_name`, `source`
  (`native|mcp|skills|policy|runner|unknown`), `arguments_summary`,
  `result_error`, `result_summary`

## TraceRecorder (in-memory)

`AgentCore::Observability::TraceRecorder` is a drop-in instrumenter that stores
events in memory (useful for tests and audits).

Capture levels:

- `:none` — record nothing
- `:safe` — record safe keys + truncate large fields
- `:full` — record full payload (still size-limited)

Use `redactor:` for app-specific PII/secret masking.
