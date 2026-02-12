# Tool Calling (Research / Reliability Case Study)

This document describes the **tool calling reliability experiment**: making
multi-turn tool use reliable across OpenAI-compatible providers and models.

Focus (now):
- deterministic tool loop behavior (CI tests)
- explicit configuration surface (context + presets)
- multi-model/provider evaluation harness (optional, OpenRouter)

Out of scope (for now):
- agent-driven character / lorebook generation workflows (deferred; no final tech route yet)
  - see `docs/todo/vibe_tavern/deferred-agentic-generation.md`
- UI/editor product flows (this doc is infra + experiments only)

Related (separate protocol):
- Structured Directives (single-turn UI/state instructions): `docs/vibe_tavern/case_studies/directives.md`
- Architecture overview: `docs/vibe_tavern/design/architecture.md`

## Conclusions (current)

- Tool calling is inherently multi-turn and therefore has higher latency + more failure points than single-turn directives.
- The biggest real-world reliability bottleneck in this eval suite is **argument discipline**:
  models must shorten/retry after `ARGUMENTS_TOO_LARGE` (see `long_arguments_guard`).
- Production recommendation:
  - start from explicit presets (provider defaults + model workarounds)
  - keep `parallel_tool_calls=false` and enforce `max_tool_calls_per_turn=1`
  - keep size guardrails (`max_tool_args_bytes` / `max_tool_output_bytes`)
  - keep “empty final recovery” enabled (`fix_empty_final`)
- Eval harness uses a strict control scenario (`chat_only` must reply exactly `"Done."`).
  Treat control failures as **eval-only prompt brittleness**, not a tool calling capability gap.

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

- The infra (`lib/tavern_kit/vibe_tavern`) ships no default *product* tools.
  App-specific tools are injected from the app layer (or eval scripts).
  The infra does include optional protocol tool sources (Agent Skills and MCP),
  but they are opt-in via configuration and still flow through the same tool
  calling guardrails.
- Keep tool schemas small and cross-provider safe.
  - Tool names should be snake_case (avoid `.`).
- Keep vendor/model quirks out of the core loop.
  - Compatibility lives in opt-in transforms and presets.
- Guardrails are non-negotiable:
  - tool arg size limits
  - tool output size limits
  - (optional) per-turn tool call limits
- Reproducibility:
  - tools + request options must be part of `PromptBuilder::Plan` (via `plan.llm_options`)
    so a run is replayable/auditable.

## Code map (infra)

Core runner stack:

- `lib/tavern_kit/vibe_tavern/prompt_runner.rb`
  - single request boundary (build plan/messages, apply transforms, perform one request)
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`
  - multi-turn loop; parses tool calls, dispatches tools, appends tool results, emits trace/events

Tool injection/execution:

- `lib/tavern_kit/vibe_tavern/tools_builder.rb`
  - assemble the model-visible `tools:` surface from multiple sources, apply allow/deny,
    enforce tool-surface limits, and freeze a deterministic snapshot
- `lib/tavern_kit/vibe_tavern/tools/custom/catalog.rb`
  - app-owned list of tools and their JSON schema
- `lib/tavern_kit/vibe_tavern/tools_builder/filtered_catalog.rb`
  - allow/deny masking of a catalog (both “send surface” and “execution surface”)
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_dispatcher.rb`
  - validates tool name + args, executes tool, returns a normalized result envelope
- `lib/tavern_kit/vibe_tavern/tools_builder/composer.rb`
  - compose multiple tool-definition sets into one catalog
- `lib/tavern_kit/vibe_tavern/tool_calling/executor_builder.rb`
  - build a runtime executor/router for the model-visible tool surface
- `lib/tavern_kit/vibe_tavern/tool_calling/executor_router.rb`
  - route tool execution by tool-name prefix (`skills_*`, `mcp_*`, default)

### Optional: EasyTalk for tool parameter schemas

Tool parameter schemas are app-owned and can be provided either as raw JSON
Schema hashes, or via a schema provider (e.g. an EasyTalk model) as long as it
responds to `json_schema`.

Example (EasyTalk schema-only model):

```ruby
class StateGetParams
  include EasyTalk::Schema

  define_schema do
    property :workspace_id, String, optional: true
    property :select, T::Array[String], optional: true
  end
end

tool =
  TavernKit::VibeTavern::ToolsBuilder::Definition.new(
    name: "state_get",
    description: "Read workspace state",
    parameters: StateGetParams, # uses `.json_schema`
  )
```

Compatibility hooks (opt-in):

- `lib/tavern_kit/vibe_tavern/transforms/message_transforms.rb`
- `lib/tavern_kit/vibe_tavern/transforms/response_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_call_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/tool_result_transforms.rb`
- `lib/tavern_kit/vibe_tavern/tool_calling/presets.rb`

## Runner behavior (ToolLoopRunner)

### Tool use mode

`context[:tool_calling][:tool_use_mode]`:

- `enforced`: require at least one tool call in the run
- `relaxed`: best-effort; runs can succeed with zero tool calls
- `disabled`: never send tools (chat-only)

### Tool failure policy (enforced mode)

`context[:tool_calling][:tool_failure_policy]`:

- `fatal` (default): fail the run if any tool ends with `ok=false`
- `tolerated`: allow tool failures, but require at least one successful tool result (`ok=true`)

### Size guardrails

To reduce model variance and prevent context bloat:

- `context[:tool_calling][:max_tool_args_bytes]` (default: `200_000`)
  - oversized args are rejected before tool execution (`ARGUMENTS_TOO_LARGE`)
- `context[:tool_calling][:max_tool_output_bytes]` (default: `200_000`)
  - oversized tool outputs are replaced with a compact failure (`TOOL_OUTPUT_TOO_LARGE`)

### Tool definition surface limits

`MaxTokens` estimates **messages only**; it does not account for the size of the
`tools:` request payload (tool definitions + JSON Schemas). Large tool surfaces
can crowd out prompt content or trigger provider-side request limits.

ToolsBuilder enforces:

- `context[:tool_calling][:max_tool_definitions_count]` (default: `128`)
  - maximum number of model-exposed tools (`exposed_to_model: true`)
- `context[:tool_calling][:max_tool_definitions_bytes]` (default: `200_000`)
  - maximum JSON bytes of the model-exposed OpenAI `tools:` array

For determinism, ToolsBuilder snapshots the model-visible tool surface once per
ToolLoopRunner instance (after allow/deny masking). This prevents tool drift
across turns and avoids repeatedly materializing tool schemas.

### Per-turn tool call limit (optional)

`context[:tool_calling][:max_tool_calls_per_turn]` (Integer):

- if set, only the first N tool calls in a single assistant message are executed
- the rest are ignored and recorded in the trace/events (`ignored_tool_calls_count`)

Stability-first default:
- if the effective request sets `parallel_tool_calls: false` and no explicit max is set,
  the runner defaults to `max_tool_calls_per_turn=1` (sequential tool calls)

### Assistant content policy in tool-call turns

Some providers/models emit natural-language content alongside `tool_calls`.
To keep tool loops deterministic (and reduce language/style “bleed” into tool
turns), ToolLoopRunner enforces:

- if an assistant message contains any `tool_calls`, the assistant message
  written back into history has `content: ""`
- any stripped content is recorded in trace as a small sample (debug only)

### Empty final assistant recovery

Some providers occasionally return an empty final assistant message even after
successful tool calls.

- `context[:tool_calling][:fix_empty_final]` (default: `true`) can do a finalization retry
- by default, that retry **does not send tools** (to avoid accidental re-calls)
  - override: `context[:tool_calling][:fix_empty_final_disable_tools]=false`

## Configuration surface (context + presets)

The source of truth is `context[:tool_calling]` (Hash). Presets are optional
sugar to compose settings explicitly:

```ruby
context_tool_calling =
  TavernKit::VibeTavern::ToolCalling::Presets.for(
    provider: "openrouter",
    model: model,
  )
```

Provider/model request overrides:

- `context[:tool_calling][:request_overrides]` is merged into the OpenAI-compatible request body.
- Reserved keys are ignored to avoid cross-layer ownership bugs:
  `model`, `messages`, `tools`, `tool_choice`, `response_format`

For provider-wide defaults shared across protocols (e.g. temperature),
prefer storing them on the LLM provider config and injecting them into
`RunnerConfig` via `llm_options_defaults:` (PromptRunner is transport-only).

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
- (when strategy matrix is enabled) `summary_by_scenario_and_strategy.json`

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
# One command: run both tool calling + directives (full preset).
OPENROUTER_API_KEY=... bundle exec ruby script/llm_vibe_tavern_eval.rb

# Full matrix (tool calling only): all models + sampling profiles + scenarios + strategies.
OPENROUTER_API_KEY=... OPENROUTER_EVAL_PRESET=full bundle exec ruby script/llm_tool_call_eval.rb

# Stable subset (cheap)
OPENROUTER_API_KEY=... bundle exec ruby script/llm_tool_call_eval.rb

# Full catalog
OPENROUTER_API_KEY=... OPENROUTER_MODEL_FILTER=all bundle exec ruby script/llm_tool_call_eval.rb

# All scenarios (heavier)
OPENROUTER_API_KEY=... OPENROUTER_SCENARIOS=all bundle exec ruby script/llm_tool_call_eval.rb

# Scenario selection (simple/typical/extreme)
OPENROUTER_API_KEY=... OPENROUTER_SCENARIOS=simple bundle exec ruby script/llm_tool_call_eval.rb
OPENROUTER_API_KEY=... OPENROUTER_SCENARIOS=typical bundle exec ruby script/llm_tool_call_eval.rb
OPENROUTER_API_KEY=... OPENROUTER_SCENARIOS=extreme bundle exec ruby script/llm_tool_call_eval.rb

# Compare eval strategies (baseline vs production-recommended model workarounds).
# - default: production only
# - matrix: baseline + production (adds `summary_by_scenario_and_strategy.json`)
OPENROUTER_API_KEY=... OPENROUTER_STRATEGY_MATRIX=1 bundle exec ruby script/llm_tool_call_eval.rb

# Sampling-parameter matrix (temperature/top_p/top_k/min_p) using predefined profiles.
# Profiles are defined in script/openrouter_sampling_profiles.rb.
OPENROUTER_API_KEY=... OPENROUTER_TRIALS=10 \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

Troubleshooting:

```sh
# If a run wrote per-run JSON files but crashed before writing the summary files,
# regenerate summaries from an existing report directory (no network calls).
bundle exec ruby script/llm_tool_call_eval_summarize.rb tmp/llm_tool_call_eval_reports/<timestamp>
```

### Eval strategies (baseline vs production)

The harness supports three strategies:

- `production` (default): applies model-specific workarounds from `ModelCatalog`
  (via `ToolCalling::Presets`), e.g. DeepSeek/Gemini OpenRouter compatibility or
  content-tag fallback for weaker tool-call emitters.
- `baseline`: disables model-specific workarounds (provider defaults + generic
  normalization only), to quantify how much the workarounds matter.
- `raw`: disables **both** model-specific workarounds and infra/provider
  presets (no response/tool-call transforms; no provider defaults). This is a
  “raw tool calling” control group to estimate how much reliability comes from
  the runner/presets themselves.

Env:
- `OPENROUTER_STRATEGY_FILTER=production` (default), or `baseline,production`
- `OPENROUTER_STRATEGY_MATRIX=1` (baseline + production)
- For the full set (incl. raw): `OPENROUTER_STRATEGY_FILTER=raw,baseline,production`

Eval note:
- some scenarios enforce a deterministic final assistant sentence (e.g. `"Done."`)
  to keep assertions stable; this is not a production prompt pattern.

Operational note:
- `SimpleInference` composes URLs as `base_url + api_prefix + endpoint`.
  - Recommended for OpenRouter: `OPENROUTER_BASE_URL=https://openrouter.ai/api` and `OPENROUTER_API_PREFIX=/v1`
  - If you set `OPENROUTER_BASE_URL=https://openrouter.ai/api/v1`, set `OPENROUTER_API_PREFIX=""`

### Eval snapshot (OpenRouter, all models, sampling matrix)

Raw report JSON files are written under `tmp/llm_tool_call_eval_reports/<timestamp>/`
and are not committed. The tables below are a captured snapshot for reference.

Command:

```sh
OPENROUTER_TRIALS=5 OPENROUTER_MODEL_FILTER=all \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  OPENROUTER_STRATEGY_FILTER="raw,baseline,production" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

Snapshot: 2026-02-08 (OpenRouter), 17 models, 5 scenarios, 5 trials per model/profile/strategy.

Note:
- This is a strategy matrix run: `raw` vs `baseline` vs `production`.
- Each model/profile has 25 runs per strategy: 20 “tool scenario” runs + 5 control runs (`chat_only`).
- Use “tool scenarios only” for tool-calling reliability; `chat_only` is a strict prompt-adherence control.

Strategy summary:

| strategy | overall | tool scenarios only | control (`chat_only`) | tool p50_ms | tool p95_ms | top error categories |
|---|---:|---:|---:|---:|---:|---|
| `raw` | 593/725 (82%) | 496/580 (86%) | 97/145 (67%) | 8605 | 20366 | `ASSERTION_FAILED`(84), `NO_TOOL_USE_ENDPOINT`(20), `NO_TOOL_CALLS`(15), `TOOL_ERROR`(6), `FORBIDDEN`(5) |
| `baseline` | 587/725 (81%) | 487/580 (84%) | 100/145 (69%) | 8113 | 19592 | `ASSERTION_FAILED`(90), `NO_TOOL_USE_ENDPOINT`(20), `NO_TOOL_CALLS`(16), `FORBIDDEN`(4), `TOOL_ERROR`(3) |
| `production` | 606/725 (84%) | 503/580 (87%) | 103/145 (71%) | 8241 | 20636 | `ASSERTION_FAILED`(107), `NO_TOOL_CALLS`(10), `TOOL_ERROR`(1), `TIMEOUT`(1) |

By scenario (ok / runs):

| scenario | raw | baseline | production | notes |
|---|---:|---:|---:|---|
| `happy_path` | 135/145 (93%) | 136/145 (94%) | 136/145 (94%) | - |
| `missing_workspace_id` | 133/145 (92%) | 127/145 (88%) | 133/145 (92%) | - |
| `type_error_recovery` | 124/145 (86%) | 123/145 (85%) | 126/145 (87%) | - |
| `long_arguments_guard` | 104/145 (72%) | 101/145 (70%) | 108/145 (74%) | hardest |
| `chat_only` | 97/145 (67%) | 100/145 (69%) | 103/145 (71%) | strict eval-only control |

Production best-per-model (tool scenarios only; best sampling profile per model):

| model | best profile | tool ok | tool p95_ms | recommended? | notes |
|---|---|---:|---:|---|---|
| `anthropic/claude-opus-4.6:nitro` | `default` | 20/20 (100%) | 13474 | Yes | - |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` | 20/20 (100%) | 18109 | Yes | - |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_general_conversation` | 19/20 (95%) | 47625 | Conditional | Very profile-sensitive (default/local were much weaker in this snapshot). |
| `google/gemini-2.5-flash:nitro` | `default` | 20/20 (100%) | 9842 | Yes | - |
| `google/gemini-3-flash-preview:nitro` | `default` | 20/20 (100%) | 9807 | Yes | - |
| `google/gemini-3-pro-preview:nitro` | `default` | 18/20 (90%) | 23951 | Conditional | Misses concentrated in `long_arguments_guard`. |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` | 20/20 (100%) | 15550 | Yes (tool scenarios) | `chat_only` control is brittle on some routes. |
| `openai/gpt-5.2-chat:nitro` | `default` | 20/20 (100%) | 13873 | Yes (tool scenarios) | `chat_only` control is brittle on some routes. |
| `openai/gpt-5.2:nitro` | `default` | 20/20 (100%) | 13648 | Yes | - |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` | 20/20 (100%) | 8119 | Yes | Avoid `qwen_recommended` for tool calling in this harness. |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` | 20/20 (100%) | 15635 | Yes | - |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` | 20/20 (100%) | 11090 | Yes | - |
| `x-ai/grok-4.1-fast` | `default` | 20/20 (100%) | 29065 | Conditional | Provider-level 403s can still appear depending on routing. |
| `z-ai/glm-4.7:nitro` | `default` | 20/20 (100%) | 16992 | Yes (tool scenarios) | `chat_only` control is brittle on some routes. |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` | 12/20 (60%) | 13041 | No (tool calling) | - |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` | 17/20 (85%) | 95212 | No (tool calling) | Very slow and still misses tool scenarios. |
| `minimax/minimax-m2-her` | `default` | 0/20 (0%) | 28797 | No (tool calling) | No tool-use endpoints on OpenRouter in this harness. |

Notable observations:
- `long_arguments_guard` is the main reliability bottleneck in this snapshot (~70–74% across strategies).
  It exercises `max_tool_args_bytes` (`ARGUMENTS_TOO_LARGE`) and requires the model to retry with a shorter payload.
- “Raw” vs “production” deltas were modest on tool scenarios (86% vs 87%).
  - Production removed `NO_TOOL_USE_ENDPOINT` errors (provider capability mismatches), but had more `ASSERTION_FAILED`.
  - Treat these strategy differences as a prompt/harness signal; real production flows do not require final text to be exactly `"Done."`.
- Model-level notes:
  - `deepseek/deepseek-v3.2` was highly sampling-profile sensitive for tool calling in this snapshot.
  - Avoid `minimax/minimax-m2-her` and `z-ai/glm-4.7-flash` for tool calling in this harness.

## Decisions (tool calling only)

We treat these as **production defaults** (reliability > latency).

- Parallel tool calls:
  - Default: sequential tool use only (`parallel_tool_calls=false` + `max_tool_calls_per_turn=1`).
  - When a model still emits multiple tool calls in one turn, we execute only the first N (default 1) and record the rest as ignored.
  - True parallel execution is treated as an explicit optimization for independent, read-only tools (future work, opt-in).
- Streaming:
  - Default: **no streaming** during tool-call turns (arguments must be complete and provider delta shapes vary too much).
  - If/when we add streaming, scope it to:
    - chat-only runs (no tools), and
    - the final assistant turn after tools (tools disabled / tool_choice none).
- Tool result envelope shape:
  - Fixed contract: keep tool results small and uniform (see `ToolDispatcher` envelope: `ok/tool_name/data/warnings/errors`).
  - Keep debugging details out-of-band (trace/events), not inside tool results.

## Production config (tool calling) and model recommendations

This table is **only** about tool calling (not directives).

Legend:
- Base preset for OpenRouter: `ToolCalling::Presets.provider_defaults("openrouter")`
- “-” means “no extra workaround” (keep `ToolCalling::Presets.default_tool_calling` + provider defaults).
- `deepseek_openrouter_compat`: `ToolCalling::Presets.deepseek_openrouter_compat`
- `gemini_openrouter_compat`: `ToolCalling::Presets.gemini_openrouter_compat`
- `content_tag_tool_call_fallback`: `ToolCalling::Presets.content_tag_tool_call_fallback`
- `tool_use_disabled`: `ToolCalling::Presets.tool_calling(tool_use_mode: :disabled)`

| model | recommended sampling profile(s) | preset/workaround | recommended? | notes |
|---|---|---|---|---|
| `anthropic/claude-opus-4.6:nitro` | `default` (no overrides) | - | Yes | 100% tool scenarios in this snapshot. |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` (no overrides) | `deepseek_openrouter_compat` | Yes | 100% tool success in this snapshot. |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_general_conversation` (t=1.3 top_p=0.95) | `deepseek_openrouter_compat` | Conditional | Highly profile-sensitive here (default/local were much weaker); misses were concentrated in `long_arguments_guard`. |
| `google/gemini-2.5-flash:nitro` | `default` (no overrides) | `gemini_openrouter_compat` | Yes | `gemini_2_5_flash_creative` was also 100% in this snapshot. |
| `google/gemini-3-flash-preview:nitro` | `default` (no overrides) | `gemini_openrouter_compat` | Yes | 100% tool success in this snapshot. |
| `google/gemini-3-pro-preview:nitro` | `default` (no overrides) | `gemini_openrouter_compat` | Conditional | 90% tool success in this snapshot; misses were concentrated in `long_arguments_guard`. |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` (t=0.6 top_p=0.95) | - | Yes (tool scenarios) | Tool scenarios were 100%, but the strict `chat_only` control prompt was brittle. |
| `openai/gpt-5.2:nitro` | `default` (no overrides) | - | Yes | 100% tool scenarios in this snapshot. |
| `openai/gpt-5.2-chat:nitro` | `default` (no overrides) | - | Yes (tool scenarios) | 100% tool scenarios in this snapshot (control prompt still brittle on some routes). |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` (no overrides) | `content_tag_tool_call_fallback` | Yes | `qwen_recommended` hurt tool calling here; prefer `default`. |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` / `qwen_recommended` | - | Yes | 100% tool scenarios across both profiles in this snapshot. |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` / `qwen_recommended` | - | Yes | 100% tool scenarios across both profiles in this snapshot. |
| `x-ai/grok-4.1-fast` | `grok_default` (t=0.3) | - | Conditional | Tool scenarios were strong (up to 100% depending on profile), but provider-level 403s and strict control brittleness still appeared. |
| `z-ai/glm-4.7:nitro` | `default` (no overrides) | `content_tag_tool_call_fallback` | Yes (tool scenarios) | 100% tool scenarios in this snapshot (control prompt still brittle on some routes). |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` (t=0.7 top_p=1.0) | `content_tag_tool_call_fallback` | No (for tool calling) | ~60% tool success in this snapshot. |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` (t=1.0 top_p=0.95 top_k=40) | `content_tag_tool_call_fallback` | No (for tool calling) | Very slow and still misses tool scenarios (concentrated in `long_arguments_guard`). |
| `minimax/minimax-m2-her` | `default` (no overrides) | `tool_use_disabled` | No (for tool calling) | Tool use disabled (capability mismatch for this harness). |
