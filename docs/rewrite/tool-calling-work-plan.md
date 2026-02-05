# Tool Calling Work Plan

This plan tracks the next set of improvements to the Tool Calling PoC and its
evaluation harness. It is intended as a checklist for acceptance (CI + behavior)
and as a record of why changes were made.

Scope:
- OpenAI-compatible providers only (OpenAI / OpenRouter / VolcanoEngine).
- Keep `ToolLoopRunner` as an orchestration skeleton (no vendor/model quirks in
  the main loop; quirks live in opt-in transforms/presets).

Out of scope (for now):
- Native transports for Anthropic/Gemini APIs (non-OpenAI message/tool shapes).

## Work Items (Acceptance Checklist)

### 1) Align `enforced` semantics with eval scenarios

- [x] Add `runtime[:tool_calling][:tool_failure_policy]` (`fatal|tolerated`).
  - `fatal` (default): current behavior (final run fails if any tool ends in `ok=false`).
  - `tolerated`: allow tool failures, but require at least one successful tool result (`ok=true`).
- [x] Update eval scenarios to use `tool_failure_policy=tolerated` where appropriate (e.g. `tool_output_truncation`).
- [x] Add/adjust tests to cover both policies.

Acceptance:
- `tool_use_mode=enforced` + `tool_failure_policy=fatal` keeps existing behavior.
- `tool_use_mode=enforced` + `tool_failure_policy=tolerated` can pass the
  “state_get fails (TOOL_OUTPUT_TOO_LARGE) but state_patch succeeds” flow.

### 2) Close `parse_args` size-guard loophole

- [x] Apply argument size checks for `arguments` received as `Hash`/`Array`
  (not only JSON strings).
- [x] Add a regression test where the provider returns `arguments` as an object
  exceeding `max_tool_args_bytes`, and the run produces `ARGUMENTS_TOO_LARGE`.

Acceptance:
- No path allows oversized tool args to reach tool execution.

### 3) Make eval runs more stable across models

- [x] Default `parallel_tool_calls=false` in eval runs (unless explicitly overridden).
- [x] Opt in `parallel_tool_calls=true` only for scenarios that require multiple
  tool calls in a single assistant response.

Acceptance:
- Single-tool-per-turn scenarios stop being polluted by occasional multi-tool turns.
- Multi-tool scenarios remain possible and explicitly opt-in.

### 4) Remove deprecated aliases / compatibility keys

- [x] Keep only canonical `runtime[:tool_calling]` keys (remove old alias keys and
  back-compat transform names introduced during PoC).
- [x] Update docs/tests accordingly.

Acceptance:
- One canonical name per setting/transform (no silent alias resolution).
- Tests and docs reflect the canonical interface only.

### 5) Quality gates

- [x] `bin/rubocop` passes.
- [x] `bin/rails test test/tool_calling/` passes.
- [x] `bin/brakeman --no-pager` remains clean (no new warnings in eval script).

### 6) Eval harness guardrails

- [x] Add configurable client timeouts to avoid long-tail runs.
  - `OPENROUTER_CLIENT_TIMEOUT` (default: `120`; `0` disables)
  - `OPENROUTER_OPEN_TIMEOUT` (default: `10`; `0` disables)
  - `OPENROUTER_READ_TIMEOUT` (default: `OPENROUTER_CLIENT_TIMEOUT`; `0` disables)
  - Optional: `OPENROUTER_HTTP_ADAPTER=httpx|default`
- [x] Add a chat-only control scenario (`chat_only`) even when tool use is enabled.

Acceptance:
- Default scenario preset includes `chat_only`.
- `chat_only` forces `tool_use_mode=disabled` for that scenario and only asserts `assistant_text == "Done."`.
