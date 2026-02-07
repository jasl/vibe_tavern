# TavernKit::VibeTavern Architecture (Research Notes)

This document describes the **architecture boundaries** of `TavernKit::VibeTavern`
as implemented in this repo.

Goal:
- a stable protocol layer for multi-model/provider usage
- predictable configuration (upper-layer injection)
- deterministic tests + optional live evaluation harnesses

Non-goal:
- shipping product workflows (agentic character/lorebook generation is deferred)
  - see `docs/todo/vibe_tavern/deferred-agentic-generation.md`

## The core idea: keep protocols separable

We treat these as **separate protocols** with different failure modes:

- **Tool calling**: multi-turn, side effects (I/O) — orchestrated by the app.
- **Structured directives**: single-turn, no side effects — structured assistant content.

They can be used in the same product, but they are intentionally **not the same
command namespace** (no “shared command names” across tools vs directives).

## Layers and responsibilities

### 1) Prompt building (DSL → messages)

`TavernKit::VibeTavern` builds a `Prompt::Plan` from:
- `history` (messages)
- `runtime` (request-scoped config snapshot)
- `variables_store` (session-scoped state)
- `llm_options` (provider/model request options)
- `strict` (debug/test policy)

Key property:
- Tools / response_format / request overrides must be part of the plan’s request
  surface (`plan.llm_options`) so runs are reproducible.

### 2) Single request boundary: PromptRunner

`lib/tavern_kit/vibe_tavern/prompt_runner.rb`

Responsibilities:
- build request body from `Prompt::Plan`
- apply outbound `MessageTransforms` and inbound `ResponseTransforms`
- send one OpenAI-compatible request via `SimpleInference`
- optionally parse **structured directives** output (when enabled)

Important config capability:
- `llm_options_defaults:` can be injected at construction time (provider-level
  defaults like temperature/top_p), and merged with per-request `llm_options`.

### 3) Tool calling: ToolLoopRunner (+ injected tools)

Code:
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_registry.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_dispatcher.rb`

Responsibilities:
- parse `tool_calls`, dispatch tools, append tool result messages, loop
- enforce guardrails (arg/output sizes, optional per-turn limits)
- emit trace/events for debugging and eval reporting

Injection points (upper layer):
- tool list + JSON schema (`ToolRegistry`)
- tool allow/deny masking (`FilteredToolRegistry`)
- transforms/presets (provider/model quirks stay opt-in)

### 4) Structured directives: Schema/Parser/Validator/Runner

Code under `lib/tavern_kit/vibe_tavern/directives/`:

- `schema.rb`: builds `response_format` JSON schema (simple, allowlist optional)
- `registry.rb`: app-injected directive type allowlist + aliases + instruction text
- `parser.rb`: tolerant JSON extraction (code fences, surrounding text) + size guards
- `validator.rb`: validates envelope, canonicalizes types, drops invalid directives with warnings
- `runner.rb`: orchestrates fallback modes:
  `json_schema` → `json_object` → `prompt_only`, with optional repair retry

Directives are designed to be:
- single-turn when possible (latency win vs tool loops)
- safe to apply locally (no I/O)
- tolerant to provider variance (fallback + warnings)

### 5) Presets: explicit provider/model workarounds

Tool calling presets:
- `lib/tavern_kit/vibe_tavern/tool_calling/presets.rb`

Directives presets:
- `lib/tavern_kit/vibe_tavern/directives/presets.rb`

Principle:
- Presets are optional sugar; the source of truth is the runtime/config hash.
- Provider/model quirks are **opt-in** and composable.

Cross-protocol compatibility:
- Directives runner filters reserved keys from request overrides (`tools`,
  `tool_choice`, `response_format`) so directives presets cannot accidentally
  leak tool config into directives requests (and vice versa).

## Testing strategy

Deterministic (CI):
- fake adapter-based tests under `test/tool_calling/` pin runner behavior and
  guardrails without network flakiness.

Optional live eval (OpenRouter):
- `script/llm_tool_call_eval.rb`
- `script/llm_directives_eval.rb`

These build model/provider capability matrices and surface:
- success rate by scenario/profile/mode
- latency percentiles
- common failure categories and vendor quirks
