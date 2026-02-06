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
- [x] Add per-turn tool-loop progress printing in the eval script (default on; `VERBOSE=0|1|2`).

Acceptance:
- Default scenario preset includes `chat_only`.
- `chat_only` forces `tool_use_mode=disabled` for that scenario and only asserts `assistant_text == "Done."`.

### 7) Latency comparison

- [x] Add a parallel tool-call happy path scenario (`happy_path_parallel`) so we can compare run latency vs the sequential happy path.
- [x] Allow `OPENROUTER_SCENARIOS=default,...` to expand the smoke preset and append extra scenarios.

Acceptance:
- `OPENROUTER_SCENARIOS="default,happy_path_parallel"` runs the smoke preset plus the parallel happy path.

### 8) Extract `VibeTavern::PromptRunner` (single request boundary)

- [x] Add `TavernKit::VibeTavern::PromptRunner` to build a `Prompt::Plan`, apply outbound/inbound transforms, and perform one OpenAI-compatible request.
- [x] Refactor `ToolCalling::ToolLoopRunner` to delegate its per-turn LLM request to `PromptRunner` (tool orchestration remains in `ToolLoopRunner`).
- [x] Keep event emission contract stable (eval progress printer should not need changes).
- [x] Add tests for `PromptRunner` and ensure existing tool loop tests still pass.

Acceptance:
- `ToolLoopRunner` no longer constructs the `Prompt::Plan` directly.
- `PromptRunner` can be used for a tool-disabled single-turn request (chat-only).

### 9) Improve baseline tolerance (without json repair)

- [x] Normalize blank tool-call arguments to `{}` via a default tool-call transform.
  - Motivation: some models emit `arguments: ""` which is not valid JSON.
  - Goal: avoid extra turns caused by `ARGUMENTS_JSON_PARSE_ERROR` when an empty object would be equivalent.
- [x] Make eval workspace `state_get` more forgiving for missing JSON pointers.
  - Missing keys/indices should return `nil` in snapshots (not `INTERNAL_ERROR`).
- [x] Add a ToolLoopRunner regression test proving that blank `arguments` can still execute a tool call under the default preset.

Acceptance:
- In eval traces, `arguments: ""` no longer produces `ARGUMENTS_JSON_PARSE_ERROR` when tools accept empty args.
- `state_get` on missing select pointers returns `null` in the snapshot payload (not `INTERNAL_ERROR`).

### 10) Borrow proven robustness patterns (ST/Risu-inspired)

- [x] Normalize single-object `tool_calls` payloads (`Hash`) the same as `Array` payloads in runner parsing.
- [x] Expand lightweight arg parsing tolerance:
  - blank/whitespace arguments => `{}`
  - fenced JSON payloads (```json ... ```) are unwrapped before parse
- [x] Add an optional response-transform fallback for textual tool-call tags:
  - `assistant_content_tool_call_tags_to_tool_calls`
  - exposed as an opt-in preset (`content_tag_tool_call_fallback`)
- [x] Add an OpenAI-compatible reliability preset for upper-layer composition:
  - `openai_compatible_reliability(...)`

Acceptance:
- Tool-call runs no longer fail when a provider emits `tool_calls` as an object.
- Tool calls with blank/fenced argument text can execute without external JSON repair libraries.
- Text-tag fallback remains opt-in (default off) and does not affect standard OpenAI-compatible runs.

### 11) Eval parallelization

- [x] Add model-level parallel workers via `OPENROUTER_JOBS` (default: `1`).
- [x] Keep deterministic output ordering in `summary.json` (same order as the model catalog after `OPENROUTER_MODEL_FILTER` selection).
- [x] Keep report paths/summary shape backward-compatible.

Acceptance:
- `OPENROUTER_JOBS=1` behaves like previous serial execution.
- `OPENROUTER_JOBS>1` runs models concurrently and produces one summary/report set.

### 12) Single-run fallback A/B + model-specific compatibility presets

- [x] Add eval profile matrix mode:
  - `OPENROUTER_FALLBACK_MATRIX=1` runs `fallback_off` and `fallback_on` in one run.
  - Report rows are labeled as `model:profile`.
- [x] Add model-specific compatibility defaults in presets:
  - DeepSeek models -> `assistant_tool_calls_reasoning_content_empty_if_missing`
  - Gemini models -> `assistant_tool_calls_signature_skip_validator_if_missing`
- [x] Add regression tests for the new model defaults and signature transform behavior.

Acceptance:
- One eval execution can compare fallback on/off for the same model/scenario set.
- DS/Gemini compatibility behavior is implemented via presets/transforms, not hardcoded in runner flow.
