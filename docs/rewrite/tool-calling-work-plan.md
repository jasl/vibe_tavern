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

- [x] Add `TavernKit::VibeTavern::PromptRunner` to build a `PromptBuilder::Plan`, apply outbound/inbound transforms, and perform one OpenAI-compatible request.
- [x] Refactor `ToolCalling::ToolLoopRunner` to delegate its per-turn LLM request to `PromptRunner` (tool orchestration remains in `ToolLoopRunner`).
- [x] Keep event emission contract stable (eval progress printer should not need changes).
- [x] Add tests for `PromptRunner` and ensure existing tool loop tests still pass.

Acceptance:
- `ToolLoopRunner` no longer constructs the `PromptBuilder::Plan` directly.
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

## Directives (Structured Outputs)

Design doc: `docs/research/vibe_tavern/directives.md`

### 13) Add Directives v1 protocol module

- [x] Add `VibeTavern::Directives::Schema` (simple JSON schema + `response_format` helper).
- [x] Add `VibeTavern::Directives::Parser`:
  - robust JSON extraction (code fences / surrounding text)
  - size guardrails with categorized errors
- [x] Add `VibeTavern::Directives::Validator`:
  - required fields (`assistant_text`, `directives`)
  - directive allowlist + canonical type normalization (fallback modes)
  - patch op validation helper (for app-injected payload validators; `/draft/` + `/ui_state/` by default)

Acceptance:
- Parser/validator never raise on malformed model output (they return categorized errors).
- Valid envelopes are normalized to canonical directive types and stable shapes.

### 14) Extend `PromptRunner` to support structured directives (single request)

- [x] Add optional `structured_output: :directives_v1` to `PromptRunner.build_request(...)`.
- [x] Inject `response_format` (json_schema) when `structured_output` is enabled.
- [x] Add parse/validate behavior to `PromptRunner.perform(...)`:
  - parse directives only when this turn has no `tool_calls`
  - return `structured_output` or `structured_output_error` (no exceptions)

Acceptance:
- Existing tool-calling behavior remains unchanged.
- `bin/rails test test/tool_calling/prompt_runner_test.rb` covers ok/invalid/missing/tool_calls-skipped/too_large cases.

### 15) Add a Directives runner with fallback + repair retry

- [x] Add `VibeTavern::Directives::Runner`:
  - primary: `json_schema` (strict) structured outputs
  - fallback: `json_object` mode (if supported)
  - fallback: prompt-only JSON (no response_format)
  - optional: single repair retry when parsing/validation fails
  - returns a result object with `assistant_text`, `directives`, and error metadata
- [x] Add deterministic tests for fallback behavior using fake HTTP adapters:
  - unsupported `response_format` => falls back to json_object/prompt-only
  - invalid JSON => repair retry path

Acceptance:
- Runner can produce a usable envelope without crashing, even when the provider does not support `json_schema`.
- Error categories are preserved for evaluation/reporting.

### 16) Add live eval harness for directives (OpenRouter, optional)

- [x] Add `script/llm_directives_eval.rb` (modeled after `llm_tool_call_eval.rb`):
  - scenario set focused on protocol correctness (not business logic)
  - metrics: parse_ok/schema_ok, error categories, latency percentiles
  - default `provider.require_parameters=true` for structured-output requests

Acceptance:
- Script runs with `OPENROUTER_API_KEY=...` and produces `tmp/llm_directives_eval_reports/...`.
- Summary includes per-model success rate + a sample failure report path.

### 17) Tool loop guardrails (small, opt-in)

- [x] Add `runtime[:tool_calling][:max_tool_calls_per_turn]` (Integer, optional).
  - If set, limit tool execution to the first N tool calls per assistant response.
  - Emit `ignored_tool_calls_count` in events/trace when limiting occurs.
- [x] If `request_overrides[:parallel_tool_calls] == false` and no explicit max is set:
  - default `max_tool_calls_per_turn = 1` (stability-first behavior).
- [x] Include response `usage` (when present) in `llm_request_end` events and trace entries.

Acceptance:
- Existing `ToolLoopRunner` tests still pass.
- Eval runs with `parallel_tool_calls=false` no longer get polluted by occasional multi-tool turns (ignored tool calls are visible in traces).

### 18) Sampling parameter matrix (eval scripts)

- [x] Add `script/openrouter_sampling_profiles.rb` (sampling profiles catalog + recommended params).
- [x] Update `script/llm_directives_eval.rb` and `script/llm_tool_call_eval.rb` to run `models × sampling_profiles` (and tool eval also `× fallback` profiles).
- [x] Update docs to cover new env knobs: `OPENROUTER_SAMPLING_PROFILE_FILTER` and `OPENROUTER_LLM_OPTIONS_DEFAULTS_JSON`.
