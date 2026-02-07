# Tool Calling (Research / Reliability Case Study)

This document describes the **tool calling reliability experiment**: making
multi-turn tool use reliable across OpenAI-compatible providers and models.

Focus (now):
- deterministic tool loop behavior (CI tests)
- explicit configuration surface (runtime + presets)
- multi-model/provider evaluation harness (optional, OpenRouter)

Out of scope (for now):
- agent-driven character / lorebook generation workflows (deferred; no final tech route yet)
  - see `docs/research/vibe_tavern/deferred-agentic-generation.md`
- UI/editor product flows (this doc is infra + experiments only)

Related (separate protocol):
- Structured Directives (single-turn UI/state instructions): `docs/research/vibe_tavern/directives.md`
- Architecture overview: `docs/research/vibe_tavern/architecture.md`

## What we mean by “tool calling”

Tool calling is **multi-turn orchestration** owned by the application:

1) send messages + tool definitions
2) model returns `tool_calls`
3) app executes tools
4) app sends tool results back as tool messages
5) repeat until the model returns a final assistant message

This is inherently slower than a single request. The goal here is **correctness
and explainability first**, then model selection and performance tuning.

## Failure modes (what we see in practice)

Tool calling fails for reasons that are rare in plain chat:

- **Tool-call shape drift** across providers/models:
  - `function_call` vs `tool_calls`
  - `tool_calls` as object vs array
- **Arguments drift**:
  - `arguments` emitted as a JSON string vs a JSON object
  - blank strings (`""`), invalid JSON, or wrong types
- **Multi-tool turns**:
  - models sometimes emit multiple tool calls in one assistant response even when instructed not to
  - parallel tool calls are not uniformly supported across providers
- **Empty final assistant messages**:
  - some routes return an empty final message after tools complete
- **Size explosions**:
  - tool args or tool outputs can exceed practical limits (cost/latency/context bloat)
- **Provider quirks**:
  - some models require extra assistant fields in tool-call turns (handled via opt-in transforms/presets)

The core approach: expect variance, normalize aggressively, and keep guardrails
explicit and test-covered.

## Design principles

These rules keep the infra stable across providers/models:

- The infra (`lib/tavern_kit/vibe_tavern`) ships **no default tool definitions**.
  Tools are injected from the app layer (or eval scripts).
- Keep tool schemas small and cross-provider safe.
  - Tool names should be snake_case (avoid `.`).
- Keep vendor/model quirks out of the core loop.
  - Compatibility lives in opt-in transforms and presets.
- Guardrails are non-negotiable:
  - tool arg size limits
  - tool output size limits
  - (optional) per-turn tool call limits
- Reproducibility:
  - tools + request options must be part of `Prompt::Plan` (via `plan.llm_options`)
    so a run is replayable/auditable.

## Code map (infra)

Core runner stack:

- `lib/tavern_kit/vibe_tavern/prompt_runner.rb`
  - single request boundary (build plan/messages, apply transforms, perform one request)
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`
  - multi-turn loop; parses tool calls, dispatches tools, appends tool results, emits trace/events

Tool injection/execution:

- `lib/tavern_kit/vibe_tavern/tool_calling/tool_registry.rb`
  - app-owned list of tools and their JSON schema
- `lib/tavern_kit/vibe_tavern/tool_calling/filtered_tool_registry.rb`
  - allow/deny masking of a registry (both “send surface” and “execution surface”)
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_dispatcher.rb`
  - validates tool name + args, executes tool, returns a normalized result envelope

Compatibility hooks (opt-in):

- `lib/tavern_kit/vibe_tavern/tool_calling/message_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/response_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_call_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_result_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/presets.rb`

## Runner behavior (ToolLoopRunner)

### Tool use mode

`runtime[:tool_calling][:tool_use_mode]`:

- `enforced`: require at least one tool call in the run
- `relaxed`: best-effort; runs can succeed with zero tool calls
- `disabled`: never send tools (chat-only)

### Tool failure policy (enforced mode)

`runtime[:tool_calling][:tool_failure_policy]`:

- `fatal` (default): fail the run if any tool ends with `ok=false`
- `tolerated`: allow tool failures, but require at least one successful tool result (`ok=true`)

### Size guardrails

To reduce model variance and prevent context bloat:

- `runtime[:tool_calling][:max_tool_args_bytes]` (default: `200_000`)
  - oversized args are rejected before tool execution (`ARGUMENTS_TOO_LARGE`)
- `runtime[:tool_calling][:max_tool_output_bytes]` (default: `200_000`)
  - oversized tool outputs are replaced with a compact failure (`TOOL_OUTPUT_TOO_LARGE`)

### Per-turn tool call limit (optional)

`runtime[:tool_calling][:max_tool_calls_per_turn]` (Integer):

- if set, only the first N tool calls in a single assistant message are executed
- the rest are ignored and recorded in the trace/events (`ignored_tool_calls_count`)

Stability-first default:
- if `request_overrides[:parallel_tool_calls] == false` and no explicit max is set,
  the runner defaults to `max_tool_calls_per_turn=1`

### Empty final assistant recovery

Some providers occasionally return an empty final assistant message even after
successful tool calls.

- `runtime[:tool_calling][:fix_empty_final]` (default: `true`) can do a finalization retry
- by default, that retry **does not send tools** (to avoid accidental re-calls)
  - override: `runtime[:tool_calling][:fix_empty_final_disable_tools]=false`

## Configuration surface (runtime + presets)

The source of truth is `runtime[:tool_calling]` (Hash). Presets are optional
sugar to compose settings explicitly:

```ruby
runtime_tool_calling =
  TavernKit::VibeTavern::ToolCalling::Presets.for(
    provider: "openrouter",
    model: model,
  )
```

Provider/model request overrides:

- `runtime[:tool_calling][:request_overrides]` is merged into the OpenAI-compatible request body.
- Reserved keys are ignored to avoid cross-layer ownership bugs:
  `model`, `messages`, `tools`, `tool_choice`, `response_format`

For provider-wide defaults shared across protocols (e.g. temperature),
prefer storing them on the LLM provider config and injecting them into
`PromptRunner` via `llm_options_defaults:`.

## Deterministic tests (CI)

Tests live under `test/tool_calling/` and intentionally cover:

- enforced vs relaxed semantics
- tool failure policies (`fatal` / `tolerated`)
- tool arg/output size limits
- tool masking (allow/deny)
- transforms/presets behavior
- loop termination + trace/event behavior

## Live eval harness (optional, OpenRouter)

Script:
- `script/llm_tool_call_eval.rb`

Outputs:
- `summary.json` and `summary_by_scenario.json` under `tmp/llm_tool_call_eval_reports/<timestamp>/`

Purpose:
- build a model×sampling profile compatibility matrix
- identify provider/model quirks early (without polluting CI)

Eval harness note:
- The live eval focuses on protocol behavior using a minimal, in-memory workspace
  and a small tool surface (typically `state_get` and `state_patch`).
- Scenario names like `missing_workspace_id` are eval harness checks for argument
  correctness; they are not a commitment to a final product state model.

### Running

```sh
# Stable subset (cheap)
OPENROUTER_API_KEY=... bundle exec ruby script/llm_tool_call_eval.rb

# Full catalog
OPENROUTER_API_KEY=... OPENROUTER_MODEL_FILTER=all bundle exec ruby script/llm_tool_call_eval.rb

# Scenario selection (simple/typical/extreme)
OPENROUTER_API_KEY=... OPENROUTER_SCENARIOS=simple bundle exec ruby script/llm_tool_call_eval.rb
OPENROUTER_API_KEY=... OPENROUTER_SCENARIOS=typical bundle exec ruby script/llm_tool_call_eval.rb
OPENROUTER_API_KEY=... OPENROUTER_SCENARIOS=extreme bundle exec ruby script/llm_tool_call_eval.rb

# Sampling-parameter matrix (temperature/top_p/top_k/min_p) using predefined profiles.
# Profiles are defined in script/openrouter_sampling_profiles.rb.
OPENROUTER_API_KEY=... OPENROUTER_TRIALS=10 \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

Eval note:
- some scenarios enforce a deterministic final assistant sentence (e.g. `"Done."`)
  to keep assertions stable; this is not a production prompt pattern.

Operational note:
- `SimpleInference` composes URLs as `base_url + api_prefix + endpoint`.
  - Recommended for OpenRouter: `OPENROUTER_BASE_URL=https://openrouter.ai/api` and `OPENROUTER_API_PREFIX=/v1`
  - If you set `OPENROUTER_BASE_URL=https://openrouter.ai/api/v1`, set `OPENROUTER_API_PREFIX=""`

### Eval snapshot (OpenRouter, all models, sampling matrix)

Run: `tmp/llm_tool_call_eval_reports/20260207T123628Z`

Command:

```sh
OPENROUTER_TRIALS=10 OPENROUTER_MODEL_FILTER=all \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

Summary:
- Overall: `1198/1450` ok (`82.62%`)
- Tool scenarios only (excluding `chat_only`): `1002/1160` ok (`86.38%`)
- By scenario (ok / runs):
  - `happy_path`: `274/290` (`94.48%`)
  - `missing_workspace_id`: `272/290` (`93.79%`)
  - `type_error_recovery`: `253/290` (`87.24%`)
  - `long_arguments_guard`: `203/290` (`70.00%`) (hardest)
  - `chat_only`: `196/290` (`67.59%`)

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

## Open questions (tool calling only)

These remain intentionally experimental:

- parallel tool calls: do we want to support true multi-tool turns in production?
- streaming: do we want streaming for tool-call runs, or keep non-streaming?
- tool result envelope shape: how strict can we make it while keeping it small?
