# Tool Calling Design (Rails rewrite PoC)

This document records the current decisions and the planned implementation for
LLM tool calling in the Rails rewrite.

Scope:
- app-owned orchestration (`tool call -> execute -> tool output -> continue`)
- multi-provider support (start OpenAI-compatible; keep extension points)
- evaluation harness (offline + optional live via OpenRouter)

Non-goals (for now):
- UI implementation
- full CCv3 editor/exporter product logic

Related (separate protocol):
- Structured Directives (pseudo tool calling): `docs/rewrite/directives.md`

## Decisions (Locked In)

These are the current source-of-truth decisions for the PoC and early product
architecture.

### 1) Workspace/State model: **B**

- We will model editing state as an explicit **EditorWorkspace/Project** concept
  (separate from chat history).
- The workspace holds:
  - `facts` (strong facts / authoritative state)
  - `draft` (editable working state)
  - `locks` (what cannot be changed implicitly)
  - optional UI state (which panels/forms are active)

Rationale:
- The editor is not a linear “chat only” session; state must be addressable,
  inspectable, and auditable independent of message history.

### 2) Facts commit requires user confirmation: **A**

- The model must not self-commit facts.
- Facts changes are two-step:
  1) `facts.propose` (agent suggests)
  2) `facts.commit` (only after explicit user/UI confirmation)
- `facts.commit` is **not exposed to the model** in the model-facing tool list.

Rationale:
- Facts are “strong truth” and must not drift due to model hallucination.

### 3) Provider/API support

- Start with **OpenAI-compatible** tool calling for the first implementation and
  live testing (OpenRouter).
- The code structure must keep extension points for non-OpenAI API shapes
  (Anthropic/Claude tool_use, Gemini function calling, etc.).

Rationale:
- OpenAI-compatible endpoints cover many providers/models and are the fastest
  way to validate robustness; but we must not bake in OpenAI-only assumptions.

### 4) Prompt Plan must carry tool definitions

- Tool definitions and request options must be included in `Prompt::Plan` via
  `plan.llm_options` (for caching/auditing/fingerprints).

Rationale:
- Tools materially change the effective prompt contract and must be part of the
  plan’s “request surface” for reproducibility.

## Implementation Sketch (PoC)

### Components

1) `ToolRegistry`
   - app-owned list of tools + JSON schema (keep schemas simple and cross-provider)
   - ToolCalling **does not ship any default tool definitions**; tools are injected from the upper layer (app/scripts).
   - tool names must be cross-provider safe (avoid `.`, prefer snake_case)
   - prefer implicit context over passing identifiers (e.g. workspace is implicit; IDs in args are optional)

2) `ToolDispatcher`
   - validates tool name + args
   - executes tool
   - returns a normalized envelope `{ ok, data, warnings, errors }`

3) `PromptRunner`
   - builds prompt via `TavernKit::VibeTavern` (dialect: `:openai`)
   - applies outbound `MessageTransforms` and inbound `ResponseTransforms`
   - sends `messages + llm_options(...)` via `SimpleInference`
   - returns `assistant_message` + `finish_reason` (OpenAI-compatible shape)

4) `ToolLoopRunner`
   - delegates the per-turn LLM request to `PromptRunner`
   - parses `tool_calls`
   - executes tools, appends tool result messages, loops until final assistant
   - emits a trace (for debugging / replay / tests)

5) Structured Directives (single-turn UI/state instructions)
   - modeled as structured assistant content (JSON envelope)
   - parsed/validated by the app (no side effects)
   - designed to be used alongside tool calling, not mixed into the same command set
   - see `docs/rewrite/directives.md`

### State: in-memory first

For early tool-loop correctness and evaluation, the **eval harness** implements
an in-memory workspace store (no DB). The tool loop runner itself is storage-
agnostic: it only needs an injected tool registry + executor.

The API shape should match the future DB-backed implementation so we can swap
storage later.

## Evaluation Harness

### Offline (default in CI)

- Deterministic fake provider responses that:
  - request tools
  - test invalid args / unknown tool failures
  - test multi-step loops and termination conditions

Purpose:
- lock in tool-loop behavior without network flakiness.

### Optional live (OpenRouter)

- A separate runner that can test multiple models via OpenRouter (OpenAI
  compatible).
- Gate behind env vars (e.g., `OPENROUTER_API_KEY`, `OPENROUTER_MODEL_FILTER=...`) so
  CI stays deterministic.

Purpose:
- detect model-specific quirks in tool calling and JSON argument quality.

Note:
- The live eval scenarios often enforce a deterministic final assistant sentence (e.g. `"Done."`)
  purely to make assertions stable. This is not a production prompt pattern.

Script:

```sh
# Run the default scenario preset (smoke) for the stable model set (default) and compute success rate / latency percentiles.
# Default preset: happy_path, missing_workspace_id, type_error_recovery, long_arguments_guard, chat_only
OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Run all scenarios.
OPENROUTER_SCENARIOS=all OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Run models in parallel workers (default: 1).
# Tip: start with 2-4 to avoid provider-side rate-limit noise.
OPENROUTER_JOBS=3 OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Run fallback on/off A/B in a single script run.
OPENROUTER_FALLBACK_MATRIX=1 OPENROUTER_JOBS=3 OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Run a subset of scenarios (comma-separated). Use `default` (or empty) to run the smoke preset.
OPENROUTER_SCENARIOS="happy_path,missing_workspace_id" OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Run the smoke preset plus an extra scenario (e.g., to compare sequential vs parallel tool calls).
OPENROUTER_SCENARIOS="default,happy_path_parallel" OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Single model (exact model id)
OPENROUTER_API_KEY=... OPENROUTER_MODEL_FILTER="openai/gpt-5.2:nitro" \
  bundle exec ruby script/llm_tool_call_eval.rb

# Multiple models by provider/tags (match against model id, base id, provider, and DSL tags)
OPENROUTER_API_KEY=... OPENROUTER_MODEL_FILTER="openai,anthropic" \
  bundle exec ruby script/llm_tool_call_eval.rb

# Exclude one model from a provider subset (`!` means exclude; `*` wildcard is supported)
OPENROUTER_API_KEY=... OPENROUTER_MODEL_FILTER="google,!google/gemini-3-pro-preview:*" \
  bundle exec ruby script/llm_tool_call_eval.rb

# Some models/providers occasionally return an empty final assistant message
# even after successful tool calls. The PoC runner can optionally do a
# "finalization" retry prompt that asks the model to return a final answer.
OPENROUTER_FIX_EMPTY_FINAL=1 OPENROUTER_API_KEY=... OPENROUTER_MODEL_FILTER="qwen/qwen3-next-80b-a3b-instruct:nitro" \
  bundle exec ruby script/llm_tool_call_eval.rb

# Run a sampling-parameter matrix (temperature/top_p/top_k/min_p) using predefined profiles.
# Profiles are defined in script/openrouter_sampling_profiles.rb.
# Applicability is enforced by default: profiles only run on matching models.
OPENROUTER_SAMPLING_PROFILE_FILTER=recommended OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Include additional non-default profiles (e.g. creative/conversation/tool_calling).
OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,creative,conversation,tool_calling" OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb
```

Notes:
- Models are registered in `script/llm_tool_call_eval.rb` via a small DSL (`MODEL_CATALOG`).
  - Default (`OPENROUTER_MODEL_FILTER=stable`) runs a curated stable set (cheap to run repeatedly).
  - Use `OPENROUTER_MODEL_FILTER=all` to run the full catalog.
  - `OPENROUTER_MODEL_FILTER` is the only model-selection env knob.

### Recommended models (tool use)

The goal of `OPENROUTER_MODEL_FILTER=stable` is to keep a small, cheap, high-signal eval set for repeated runs.

As of `tmp/llm_tool_call_eval_reports/20260207T123628Z` (full model catalog, smoke scenarios, 10 trials, sampling profile matrix),
the strict end-to-end success rate was:

- Overall: `1198/1450` ok (`82.62%`)
- Tool scenarios only (excluding `chat_only`): `1002/1160` ok (`86.38%`)
- By scenario (ok / runs):
  - `happy_path`: `274/290` (`94.48%`)
  - `missing_workspace_id`: `272/290` (`93.79%`)
  - `type_error_recovery`: `253/290` (`87.24%`)
  - `long_arguments_guard`: `203/290` (`70.00%`) (hardest)
  - `chat_only`: `196/290` (`67.59%`)

Command:

```sh
OPENROUTER_TRIALS=10 OPENROUTER_MODEL_FILTER=all \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

100% model/profile combos in this snapshot (50/50):

| model | sampling_profile | ok | p95_ms | notes |
|---|---|---:|---:|---|
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `qwen_recommended` | 50/50 | 8718 | - |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` | 50/50 | 9131 | best-effort enables the content-tag fallback |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `qwen_recommended` | 50/50 | 12059 | - |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` | 50/50 | 12179 | - |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` | 50/50 | 12633 | - |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` | 50/50 | 13206 | - |
| `anthropic/claude-opus-4.6:nitro` | `default` | 50/50 | 18392 | - |

Near-perfect (>= 96%) combos in this snapshot:
- `openai/gpt-5.2:nitro` + `default`: `49/50` (`98%`)
- `google/gemini-2.5-flash:nitro` + `default`: `49/50` (`98%`)
- `google/gemini-3-flash-preview:nitro` + `default`: `48/50` (`96%`)

Notable observations:
- The most frequent failure reason was the strict final text constraint (`assistant_text == "Done."`). This is an eval-only constraint used to keep assertions stable.
- `long_arguments_guard` is the main reliability bottleneck in this run (70%). It exercises `max_tool_args_bytes` (`ARGUMENTS_TOO_LARGE`) and requires the model to retry with a shorter payload.
- Provider quirks: `x-ai/grok-4.1-fast` returned HTTP 403 for `chat_only` in this run (OpenRouter/xAI safety false-positive: `SAFETY_CHECK_TYPE_BIO`).
- Sampling profile impact (high-level):
  - DeepSeek V3.2: `deepseek_v3_2_creative_writing` was the worst profile (78%); `default` / `deepseek_v3_2_local_recommended` were best (92%).
  - Gemini 2.5 Flash: `gemini_2_5_flash_creative` was 100%; `default` was 98%.
  - Qwen 3 235B: `default` was 100%, but `qwen_recommended` dropped to 80% (all misses in `long_arguments_guard`).

Models outside `stable` can be valuable, but tend to be noisier on at least one scenario (most commonly `long_arguments_guard`) or have more provider-side variability.
- `SimpleInference` composes the final request URL as `base_url + api_prefix + endpoint`.
  - Recommended for OpenRouter: `OPENROUTER_BASE_URL=https://openrouter.ai/api` and `OPENROUTER_API_PREFIX=/v1`
  - If you already set `OPENROUTER_BASE_URL=https://openrouter.ai/api/v1`, set `OPENROUTER_API_PREFIX=""`
- Client timeouts (eval-only; seconds):
  - `OPENROUTER_CLIENT_TIMEOUT` (default: `120`; `0` disables)
  - `OPENROUTER_OPEN_TIMEOUT` (default: `10`; `0` disables)
  - `OPENROUTER_READ_TIMEOUT` (default: `OPENROUTER_CLIENT_TIMEOUT`; `0` disables)
  - HTTP adapter: `OPENROUTER_HTTP_ADAPTER=httpx|default` (default: `httpx`)
- Progress output (eval-only):
  - `VERBOSE=0` to disable per-turn progress lines
  - `VERBOSE=1` (default) shows tool-loop progress for each run
  - `VERBOSE=2` includes extra request/tool size info
  - `OPENROUTER_JOBS` controls model-level parallel workers (default: `1`)
  - `OPENROUTER_FALLBACK_MATRIX=1` runs both `fallback_off` and `fallback_on` profiles in one pass
  - Sampling-parameter matrix (temperature/top_p/top_k/min_p):
    - `OPENROUTER_SAMPLING_PROFILE_FILTER` (default: `default`; matches id/tags in `script/openrouter_sampling_profiles.rb`)
    - `OPENROUTER_SAMPLING_PROFILE_ENFORCE_APPLICABILITY=1` (default) applies profiles only to matching models
    - Optional global overrides: `OPENROUTER_LLM_OPTIONS_DEFAULTS_JSON`, `OPENROUTER_TEMPERATURE`, `OPENROUTER_TOP_P`, `OPENROUTER_TOP_K`, `OPENROUTER_MIN_P`
  - Best-effort defaults:
    - The script may enable some compatibility presets per model (registered in `MODEL_CATALOG`) to improve tool calling reliability.
    - `OPENROUTER_ENABLE_CONTENT_TAG_TOOL_CALL_FALLBACK=1` forces the content-tag fallback on for all models (override).
- Tool use mode:
  - `OPENROUTER_TOOL_USE_MODE=enforced|relaxed|disabled`
    - `enforced`: require at least one tool call; final failure behavior is controlled by `tool_failure_policy`
    - `relaxed`: best-effort; optional retry budget controls whether we retry without tools on provider errors
    - `disabled`: never send tools (chat-only mode)
  - This is also a pipeline/runtime setting: `runtime[:tool_calling][:tool_use_mode]`
- Tool failure policy (when `tool_use_mode=enforced`):
  - `OPENROUTER_TOOL_FAILURE_POLICY=fatal|tolerated` (default: `fatal`)
  - Pipeline/runtime setting: `runtime[:tool_calling][:tool_failure_policy]`
    - `fatal`: fail the run if any tool ends with `ok=false`
    - `tolerated`: allow tool failures, but require at least one successful tool result (`ok=true`)
- Tool size guardrails (to reduce provider/model variance and avoid context bloat):
  - `runtime[:tool_calling][:max_tool_args_bytes]` (default: 200_000)
    - If tool arguments exceed this size, the tool result is replaced with `{ ok:false, errors:[ARGUMENTS_TOO_LARGE] }`
  - `runtime[:tool_calling][:max_tool_output_bytes]` (default: 200_000)
    - If tool output exceeds this size, the tool message content is replaced with `{ ok:false, errors:[TOOL_OUTPUT_TOO_LARGE] }`
- Tool choice (OpenAI-compatible):
  - Default is `"auto"` (let the model decide).
  - Override via `runtime[:tool_calling][:tool_choice]` (String/Symbol/Hash) when needed.
    - Example: `"none"` to force chat-only even when tools are present.
- Optional retry budget (only used in `tool_use_mode=relaxed`):
  - `OPENROUTER_TOOL_CALLING_FALLBACK_RETRY_COUNT=0` (default; no automatic retries)
  - Pipeline/runtime setting: `runtime[:tool_calling][:fallback_retry_count]`
- By default, the eval script uses a minimal tool allowlist (only `state_get` and `state_patch`)
  to reduce model variance.
  - Override: `OPENROUTER_TOOL_ALLOWLIST=state_get,state_patch`
  - Expose all model-facing tools (not recommended for reliability checks): `OPENROUTER_TOOL_ALLOWLIST=all`
- Tool masking can be controlled via runtime config (so app code can
  change the tool surface without prompt edits):
  - `runtime[:tool_calling][:tool_allowlist]`:
    - explicit allowlist (Array or comma-separated String)
  - `runtime[:tool_calling][:tool_denylist]`:
    - explicit denylist (Array or comma-separated String)
  - Masking is enforced both when sending tools **and** when executing tool calls
    (so the model cannot call hidden tools).
  - Implementation rule: tools in the denylist are not included in the `tools:` list
    at all (we do not rely on "don't call X" prompt instructions).

Note:
- A "tool profile" is an app-layer convenience that resolves to allow/deny lists.
  The tool loop runner only consumes allow/deny lists to keep responsibilities
  clean and avoid hidden coupling between profile names and lower-level code.
- Optional sugar exists in `TavernKit::VibeTavern::ToolCalling::Presets` to build
  `runtime[:tool_calling]` hashes, but the runtime hash remains the source of truth.
- The tool loop can optionally do a "finalization retry" when a provider returns an empty
  final assistant message even after successful tool calls.
  - This is configured as a pipeline/runtime setting (`runtime[:tool_calling][:fix_empty_final]`)
  - Default: enabled
  - Eval override: `OPENROUTER_FIX_EMPTY_FINAL=0` to disable
  - Optional prompt override: `runtime[:tool_calling][:fix_empty_final_user_text]` (String)
  - By default, the finalization retry does **not** send tools (so the model cannot re-call tools by accident).
    - Override: `runtime[:tool_calling][:fix_empty_final_disable_tools]=false`
- Provider/request-level overrides (upper-layer injection):
  - `runtime[:tool_calling][:request_overrides]` (Hash) is merged into the OpenAI-compatible request body.
    - Intended for provider-specific knobs like OpenRouter routing (`route`, `provider`, `transforms`) or standard params (`temperature`).
    - Reserved keys are ignored here (`model`, `messages`, `tools`, `tool_choice`, `response_format`) to keep ownership clear.
    - For provider-wide defaults shared across protocols (e.g. `temperature`), prefer storing them on the LLM provider config and injecting them via `PromptRunner` `llm_options_defaults`.
  - Eval env helpers (optional):
    - `OPENROUTER_ROUTE=fallback`
    - `OPENROUTER_TRANSFORMS=middle-out` (comma-separated)
    - `OPENROUTER_PROVIDER_ONLY=...`, `OPENROUTER_PROVIDER_ORDER=...`, `OPENROUTER_PROVIDER_IGNORE=...` (comma-separated)
    - `OPENROUTER_REQUEST_OVERRIDES_JSON='{\"temperature\":0.2}'` (advanced; JSON object)
- Provider/model message transforms (upper-layer injection):
  - `runtime[:tool_calling][:message_transforms]` (Array or comma-separated String) applies opt-in transforms to outbound messages before dispatch.
  - Built-ins: `assistant_tool_calls_content_null_if_blank`, `assistant_tool_calls_reasoning_content_empty_if_missing`, `assistant_tool_calls_signature_skip_validator_if_missing`
- Provider/model tool transforms (upper-layer injection):
  - `runtime[:tool_calling][:tool_transforms]` (Array or comma-separated String) applies opt-in transforms to the outbound `tools:` list before dispatch.
  - Built-ins: `openai_tools_strip_function_descriptions`
- Provider/model response transforms (upper-layer injection):
  - `runtime[:tool_calling][:response_transforms]` (Array or comma-separated String) applies opt-in transforms to the inbound assistant message (`choices[0].message`) before parsing tool calls.
  - Built-ins: `assistant_function_call_to_tool_calls`, `assistant_tool_calls_object_to_array`, `assistant_tool_calls_arguments_json_string_if_hash`, `assistant_content_tool_call_tags_to_tool_calls` (opt-in fallback)
- Provider/model tool call transforms (upper-layer injection):
  - `runtime[:tool_calling][:tool_call_transforms]` (Array or comma-separated String) applies opt-in transforms to parsed `tool_calls` before execution.
  - Built-ins: `assistant_tool_calls_arguments_blank_to_empty_object`
- Provider/model tool result transforms (upper-layer injection):
  - `runtime[:tool_calling][:tool_result_transforms]` (Array or comma-separated String) applies opt-in transforms to tool result envelopes before serializing them into tool messages.
  - Built-ins: `tool_result_compact_envelope`
- Optional preset helpers (`TavernKit::VibeTavern::ToolCalling::Presets`):
  - `openai_compatible_reliability(...)`: conservative defaults for OpenAI-compatible tool calling.
  - `content_tag_tool_call_fallback`: opt-in fallback for models/routes that emit textual `<tool_call>...</tool_call>` tags instead of structured `tool_calls`.
  - `deepseek_openrouter_compat`: DeepSeek-friendly outbound message shim.
  - `gemini_openrouter_compat`: Gemini-friendly outbound message shim.

## Model reliability metadata (tool calling)

In production, tool calling reliability varies by model/provider and may be
non-deterministic (routing, safety filters, transient provider errors).

Recommendation:
- When storing LLM connection / model configuration, record whether that model
  is considered **tool-call reliable** for `tool_use_mode=enforced`.
  - Example field: `tool_calling_reliable: true|false` (or a `reliability` enum)
- Use `tool_use_mode=enforced` only with models marked reliable.
- For non-critical flows, prefer `tool_use_mode=relaxed` (best-effort).

### Current offline coverage (regression guardrails)

The DB-free tool-loop tests intentionally cover common failure modes that show
up across real-world models/providers:
- missing required params (e.g. `workspace_id`)
- invalid JSON in tool arguments
- invalid types/paths in patch ops
- duplicate tool_call IDs
- overly large tool arguments (size limit)
- overly large tool outputs (size limit / replacement)

## Open Questions (Parking Lot)

These are intentionally deferred until we have the PoC loop + tests.

- Do we want to support parallel tool calls in a single turn?
- Do we want streaming for tool-call runs, or keep PoC non-streaming only?
- How do we standardize tool result envelopes across providers (and keep them
  small to avoid context bloat)?
- What is the minimum set of tools for the first editor prototype
  (CCv3-only, import/export later)?

## Deferred Provider Quirks (Parking Lot)

These are known, real-world provider/model quirks observed in SillyTavern/RisuAI,
but are intentionally *not* baked into lower layers yet to keep SRP and avoid
hardcoding vendor hacks. When we see stable reproduction in our own eval runs,
we can implement them as opt-in upper-layer transforms / presets.

- DeepSeek reasoner: add dummy `reasoning_content: ""` on assistant messages that include `tool_calls`
  - Motivation: some DeepSeek-*reasoner* routes reject tool-call messages without the field.
  - Implementation idea (SRP-friendly): an optional message-transform hook before dispatch.
- Gemini/Claude tool calling: request/response shape adapters (non-OpenAI formats)
  - Motivation: Gemini function calling and Claude tool_use/tool_result have strict shape/order rules.
  - Implementation idea: provider adapters in `simple_inference` (protocols), keeping pipeline/tool loop generic.
