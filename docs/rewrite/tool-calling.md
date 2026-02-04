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
   - allowlist of tools + JSON schema (keep schemas simple and cross-provider)
   - tool names must be cross-provider safe (avoid `.`, prefer snake_case)
   - prefer implicit context over passing identifiers (e.g. workspace is implicit; IDs in args are optional)

2) `ToolDispatcher`
   - validates tool name + args
   - executes tool
   - returns a normalized envelope `{ ok, data, warnings, errors }`

3) `ToolLoopRunner`
   - builds prompt via `TavernKit::VibeTavern` (dialect: `:openai`)
   - sends `messages + llm_options(tools, tool_choice, ...)` via `SimpleInference`
   - parses `tool_calls`
   - executes tools, appends tool result messages, loops until final assistant
   - emits a trace (for debugging / replay / tests)

### State: in-memory first

For early tool-loop correctness and evaluation, we will implement an in-memory
workspace store (no DB). The API shape should match the future DB-backed
implementation so we can swap storage later.

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
- Gate behind env vars (e.g., `OPENROUTER_API_KEY`, `OPENROUTER_MODEL=...`) so
  CI stays deterministic.

Purpose:
- detect model-specific quirks in tool calling and JSON argument quality.

Script:

```sh
# Run each model multiple times and compute success rate / latency percentiles.
OPENROUTER_TRIALS=10 OPENROUTER_API_KEY=... \
  bundle exec ruby script/llm_tool_call_eval.rb

# Single model
OPENROUTER_API_KEY=... OPENROUTER_MODEL="openai/gpt-4.1-mini" \
  bundle exec ruby script/llm_tool_call_eval.rb

# Multiple models
OPENROUTER_API_KEY=... OPENROUTER_MODELS="openai/gpt-4.1-mini,anthropic/claude-3.5-sonnet" \
  bundle exec ruby script/llm_tool_call_eval.rb

# Some models/providers occasionally return an empty final assistant message
# even after successful tool calls. The PoC runner can optionally do a
# "finalization" retry without tools.
OPENROUTER_FIX_EMPTY_FINAL=1 OPENROUTER_API_KEY=... OPENROUTER_MODEL="qwen/qwen3-next-80b-a3b-instruct" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

Notes:
- `SimpleInference` composes the final request URL as `base_url + api_prefix + endpoint`.
  - Recommended for OpenRouter: `OPENROUTER_BASE_URL=https://openrouter.ai/api` and `OPENROUTER_API_PREFIX=/v1`
  - If you already set `OPENROUTER_BASE_URL=https://openrouter.ai/api/v1`, set `OPENROUTER_API_PREFIX=""`
- Tool use mode:
  - `OPENROUTER_TOOL_USE_MODE=enforced|relaxed|disabled`
    - `enforced`: tool calls must succeed; otherwise fail the run (surface error to UI; user can retry)
    - `relaxed`: best-effort; optional retry budget controls whether we retry without tools on provider errors
    - `disabled`: never send tools (chat-only mode)
  - This is also a pipeline/runtime setting: `runtime[:tool_calling][:tool_use_mode]`
- Optional retry budget (only used in `tool_use_mode=relaxed`):
  - `OPENROUTER_TOOL_CALLING_FALLBACK_RETRY_COUNT=0` (default; no automatic retries)
  - Pipeline/runtime setting: `runtime[:tool_calling][:fallback_retry_count]`
- By default, the eval script uses a minimal tool allowlist (only `state_get` and `state_patch`)
  to reduce model variance.
  - Override: `OPENROUTER_TOOL_ALLOWLIST=state_get,state_patch`
  - Expose all model-facing tools (not recommended for reliability checks): `OPENROUTER_TOOL_ALLOWLIST=all`
- Tool masking can be controlled via runtime config (so app code can
  change the tool surface without prompt edits):
  - `runtime[:tool_calling][:tool_names]` / `:tool_allowlist` / `:allowed_tools`:
    - explicit allowlist (Array or comma-separated String)
  - `runtime[:tool_calling][:tool_denylist]` / `:disabled_tools`:
    - explicit denylist (Array or comma-separated String)
  - Masking is enforced both when sending tools **and** when executing tool calls
    (so the model cannot call hidden tools).

Note:
- A "tool profile" is an app-layer convenience that resolves to allow/deny lists.
  The tool loop runner only consumes allow/deny lists to keep responsibilities
  clean and avoid hidden coupling between profile names and lower-level code.
- The tool loop can optionally do a "finalization retry" when a provider returns an empty
  final assistant message even after successful tool calls.
  - This is configured as a pipeline/runtime setting (`runtime[:tool_calling][:fix_empty_final]`)
  - Default: enabled
  - Eval override: `OPENROUTER_FIX_EMPTY_FINAL=0` to disable

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
