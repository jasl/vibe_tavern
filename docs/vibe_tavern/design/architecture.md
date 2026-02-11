# TavernKit::VibeTavern Architecture

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

### 0) Unified configuration + invariants: RunnerConfig / Capabilities / Preflight

VibeTavern treats configuration as **programmer-owned** and **request-scoped**.
To keep call sites consistent, we use a single entrypoint object:

- `lib/tavern_kit/vibe_tavern/runner_config.rb`

`RunnerConfig` is responsible for:
- accepting a request-scoped `context` snapshot (Symbol keys)
- building a per-run configured pipeline (step options)
- normalizing `llm_options_defaults` (Symbol keys; reserved keys rejected)
- parsing module-local configs:
  - `ToolCalling::Config`
  - `Directives::Config`
  - `LanguagePolicy::Config`
  - `OutputTags::Config`
- producing a capabilities snapshot (`Capabilities.resolve`) used for routing
  decisions and strict invariants
  - registry-driven overrides live in:
    - `lib/tavern_kit/vibe_tavern/capabilities_registry.rb`
  - unknown provider/model defaults are intentionally conservative (do not
    assume `json_schema` support)
  - capabilities can optionally include prompt budget fields:
    - `context_window_tokens` (app-chosen context window cap)
    - `reserved_response_tokens` (tokens reserved for the model response)
    - when configured, the VibeTavern pipeline enforces the prompt budget via
      `TavernKit::PromptBuilder::Steps::MaxTokens` (step name: `:max_tokens`)
    - global defaults can be set via:
      `TavernKit::VibeTavern::CapabilitiesRegistry.configure_default_overrides(...)`

Hard invariants are enforced centrally in:
- `lib/tavern_kit/vibe_tavern/preflight.rb`

Request normalization is applied centrally in:
- `lib/tavern_kit/vibe_tavern/request_policy.rb`
  - structured outputs force `parallel_tool_calls: false` in internal options
  - `parallel_tool_calls` is removed from the outbound request when the current
    provider/model capabilities do not support sending the field

Examples:
- tools and `response_format` are mutually exclusive in a single request
- streaming is not supported for tool calling / response_format in this layer

### 1) Prompt building (DSL → messages)

`TavernKit::VibeTavern` builds a `PromptBuilder::Plan` from:
- `history` (messages)
- `context` (request-scoped config snapshot)
- `variables_store` (session-scoped state)
- `llm_options` (provider/model request options)
- `strict` (debug/test policy)

Key property:
- Tools / response_format / request overrides must be part of the plan’s request
  surface (`plan.llm_options`) so runs are reproducible.

PromptBuilder API contract (V2):
- `PromptBuilder.new(...)` accepts fixed keyword inputs (`character`, `user`,
  `history`, `message`, `preset`, `dialect`, `strict`, `llm_options`, etc.)
  plus `configs:` for step-level overrides.
- `context` remains the single external input truth; `state` is internal
  mutable build state only.
- Unknown step names in `context.module_configs` are ignored (no side effects).
- For known steps, config parsing is strict and typed via step-local
  `Step::Config.from_hash`.

### 2) Single request boundary: PromptRunner

`lib/tavern_kit/vibe_tavern/prompt_runner.rb`

Responsibilities:
- build request body from `PromptBuilder::Plan`
- apply outbound `MessageTransforms` and inbound `ResponseTransforms`
- send one OpenAI-compatible request via `SimpleInference`
- (optional) stream chat-only responses via `PromptRunner#perform_stream`

Dialect note:
- `PromptRunner` builds OpenAI-compatible ChatCompletions requests (`model` + `messages` Array).
- Use `dialect: :openai` (or another dialect that returns an OpenAI-style messages Array).
- Dialects that produce non-OpenAI payloads (e.g. `:anthropic`, `:google`) are not supported here yet.
  See `docs/todo/vibe_tavern/native-anthropic-google-and-media-apis.md`.

Streaming policy (production default):
- Tool calling turns are **non-streaming** (mutually exclusive in code).
- Streaming is intended for:
  - chat-only runs (no tools, no `response_format`), and
  - a final "answer-only" turn after tools (tools disabled; optional best-effort
    extra request via `ToolLoopRunner#run(final_stream: true)`).

PromptRunner contract (after RunnerConfig refactor):
- `PromptRunner.new(client:)` is transport-only (no config).
- `PromptRunner#build_request` requires `runner_config:` and merges:
  - `runner_config.llm_options_defaults` (provider/model defaults)
  - per-call `llm_options` (strict Symbol keys; reserved keys rejected)
- no directives parsing and no OutputTags post-processing in PromptRunner itself

### 3) Tool calling: ToolLoopRunner (+ injected tools)

Code:
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_registry.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_dispatcher.rb`

Responsibilities:
- parse `tool_calls`, dispatch tools, append tool result messages, loop
- enforce guardrails (arg/output sizes, optional per-turn limits)
- emit trace/events for debugging and eval reporting
- invariant: when an assistant message contains `tool_calls`, the assistant
  `content` written back into history is forced to `""` (prevents pollution)

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

Structured outputs invariant:
- any request using `response_format` forces `parallel_tool_calls: false`
  (via `RequestPolicy`, best-effort depending on capabilities)

### 5) Presets: explicit provider/model workarounds

Tool calling presets:
- `lib/tavern_kit/vibe_tavern/tool_calling/presets.rb`

Directives presets:
- `lib/tavern_kit/vibe_tavern/directives/presets.rb`

Principle:
- Presets are optional sugar; the source of truth is the context/config hash.
- Provider/model quirks are **opt-in** and composable.

Cross-protocol compatibility:
- Directives runner rejects tool-calling keys in request overrides (`tools`,
  `tool_choice`) and always overwrites `response_format` per mode, so directives
  presets cannot accidentally leak tool config into directives requests (and
  vice versa).

## Shared deterministic utilities (vendor)

We downshift syntax-level utilities into the embedded gem so they can be reused
across protocols without duplication:

- `TavernKit::Text::LanguageTag` (BCP-47 / RFC 5646 syntax normalization)
- `TavernKit::Text::JSONPointer` (RFC 6901 syntax tools)
- `TavernKit::Text::VerbatimMasker` (verbatim zones + escape hatch masking)

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
