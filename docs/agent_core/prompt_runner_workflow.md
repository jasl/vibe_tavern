# PromptRunner workflow (Stepper model)

`AgentCore::PromptRunner::Runner` is a state machine that advances in **turns**:

1. Build an LLM request (`messages` + optional `tools`)
2. Call the provider (`provider.chat`)
3. Append the assistant message
4. If the assistant emitted tool calls:
   - authorize each call (policy)
   - execute inline, or pause (confirm / defer)
   - append tool result messages
5. Repeat until a final assistant message is produced or `max_turns` is reached

## Pause boundaries (the only resumable states)

Runner only pauses at tool boundaries:

- `:awaiting_tool_confirmation` — a policy returned `Decision.confirm(...)`
- `:awaiting_tool_results` — a `ToolExecutor` deferred execution (e.g. `DeferAll`)

When paused, the `RunResult` includes:

- `stop_reason` (`awaiting_*`)
- `pending_tool_confirmations` or `pending_tool_executions`
- `continuation` (opaque resume token/state)

## Persisting pause state (Continuation v1)

For cross-process persistence, serialize `continuation` as a versioned JSON-safe
payload:

- `AgentCore::PromptRunner::ContinuationCodec.dump(continuation, context_keys: [...])`
- `AgentCore::PromptRunner::ContinuationCodec.load(payload)`

Only persist explicitly allowlisted `context_keys` (tenant/user/workspace ids).
Never persist secrets (tokens/headers/env).

## Deriving deferred tool tasks

When paused with `:awaiting_tool_results`, the continuation can be converted
into a stable JSON-safe task payload for schedulers:

- `AgentCore::PromptRunner::ToolTaskCodec.dump(continuation, context_keys: [...])`
- `AgentCore::PromptRunner::ToolTaskCodec.load(payload)`

Task payloads include **raw tool arguments**. Treat them as sensitive.

## Resume

- Confirm pause: `Runner#resume` / `#resume_stream`
- Deferred execution pause: `Runner#resume_with_tool_results` / `#resume_stream_with_tool_results`

`resume*_with_tool_results` supports incremental results via `allow_partial:
true`, keeping the run paused until all tool results are available.

All `resume*` methods accept either a `Continuation` object or a serialized
payload (`Hash` / JSON `String`).

## Observability events

Runner publishes structured pause/resume events (no raw tool args/results):

- `agent_core.pause` — `{ run_id, turn_number, pause_reason, pending_*_count }`
- `agent_core.resume` — `{ run_id, paused_turn_number, pause_reason, resumed: true }`
- `agent_core.tool.task.created` / `.deferred` — per-tool lifecycle (no raw args)

Use these for progress tracking, audits, and correlating out-of-band tool work.
