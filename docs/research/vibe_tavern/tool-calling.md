# Tool Calling (Research / Reliability Case Study)

This document describes the **tool calling reliability experiment**: making
multi-turn tool use reliable across OpenAI-compatible providers and models.

Focus (now):
- deterministic tool loop behavior (CI tests)
- explicit configuration surface (runtime + presets)
- multi-model/provider evaluation harness (optional, OpenRouter)

Out of scope (for now):
- agent-driven character / lorebook generation workflows (deferred; no final tech route yet)
  - see `docs/todo/vibe_tavern/deferred-agentic-generation.md`
- UI/editor product flows (this doc is infra + experiments only)

Related (separate protocol):
- Structured Directives (single-turn UI/state instructions): `docs/research/vibe_tavern/directives.md`
- Architecture overview: `docs/research/vibe_tavern/architecture.md`

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
  TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
    name: "state_get",
    description: "Read workspace state",
    parameters: StateGetParams, # uses `.json_schema`
  )
```

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

Note:
- This is a strategy matrix run: `raw` vs `baseline` vs `production`.
- Each model/profile has 25 runs per strategy: 20 “tool scenario” runs + 5 control runs (`chat_only`).
- Use “tool scenarios only” for tool-calling reliability; `chat_only` is a strict prompt-adherence control.

Strategy summary:

| strategy | overall | tool scenarios only | control (`chat_only`) | tool p50_ms | tool p95_ms | top error categories |
|---|---:|---:|---:|---:|---:|---|
| `raw` | 618/725 (85%) | 510/580 (88%) | 108/145 (74%) | 10019 | 22268 | `ASSERTION_FAILED`(76), `NO_TOOL_USE_ENDPOINT`(20), `NO_TOOL_CALLS`(7), `TIMEOUT`(4) |
| `baseline` | 605/725 (83%) | 503/580 (87%) | 102/145 (70%) | 10030 | 24474 | `ASSERTION_FAILED`(88), `NO_TOOL_USE_ENDPOINT`(20), `NO_TOOL_CALLS`(8), `TIMEOUT`(2), `UPSTREAM_5XX`(2) |
| `production` | 607/725 (84%) | 506/580 (87%) | 101/145 (70%) | 10385 | 22969 | `ASSERTION_FAILED`(106), `NO_TOOL_CALLS`(8), `FORBIDDEN`(3), `TOOL_ERROR`(1) |

By scenario (ok / runs):

| scenario | raw | baseline | production | notes |
|---|---:|---:|---:|---|
| `happy_path` | 138/145 (95%) | 140/145 (97%) | 138/145 (95%) | - |
| `missing_workspace_id` | 137/145 (94%) | 134/145 (92%) | 136/145 (94%) | - |
| `type_error_recovery` | 130/145 (90%) | 125/145 (86%) | 128/145 (88%) | - |
| `long_arguments_guard` | 105/145 (72%) | 104/145 (72%) | 104/145 (72%) | hardest |
| `chat_only` | 108/145 (74%) | 102/145 (70%) | 101/145 (70%) | strict eval-only control |

Model/profile matrix (tool scenarios only; raw vs baseline vs production):

| model | profile | raw (tool) | baseline (tool) | production (tool) | production p95_ms |
|---|---|---:|---:|---:|---:|
| `anthropic/claude-opus-4.6:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 21336 |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` | 20/20 (100%) | 19/20 (95%) | 19/20 (95%) | 12023 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_creative_writing` | 15/20 (75%) | 15/20 (75%) | 15/20 (75%) | 24537 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_general_conversation` | 16/20 (80%) | 18/20 (90%) | 17/20 (85%) | 23058 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_local_recommended` | 16/20 (80%) | 16/20 (80%) | 19/20 (95%) | 22161 |
| `deepseek/deepseek-v3.2:nitro` | `default` | 19/20 (95%) | 18/20 (90%) | 19/20 (95%) | 20359 |
| `google/gemini-2.5-flash:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 19/20 (95%) | 11423 |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 11262 |
| `google/gemini-3-flash-preview:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 19/20 (95%) | 10261 |
| `google/gemini-3-pro-preview:nitro` | `default` | 15/20 (75%) | 15/20 (75%) | 16/20 (80%) | 26139 |
| `minimax/minimax-m2-her` | `default` | 0/20 (0%) | 0/20 (0%) | 0/20 (0%) | 20703 |
| `minimax/minimax-m2.1:nitro` | `default` | 19/20 (95%) | 16/20 (80%) | 17/20 (85%) | 35266 |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` | 15/20 (75%) | 17/20 (85%) | 17/20 (85%) | 29315 |
| `moonshotai/kimi-k2.5:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 13302 |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` | 19/20 (95%) | 20/20 (100%) | 20/20 (100%) | 27417 |
| `openai/gpt-5.2-chat:nitro` | `default` | 20/20 (100%) | 19/20 (95%) | 20/20 (100%) | 15345 |
| `openai/gpt-5.2:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 12960 |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 12159 |
| `qwen/qwen3-235b-a22b-2507:nitro` | `qwen_recommended` | 18/20 (90%) | 17/20 (85%) | 17/20 (85%) | 7772 |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 13077 |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `qwen_recommended` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 13239 |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 12606 |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `qwen_recommended` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 10089 |
| `x-ai/grok-4.1-fast` | `default` | 18/20 (90%) | 20/20 (100%) | 19/20 (95%) | 32858 |
| `x-ai/grok-4.1-fast` | `grok_default` | 18/20 (90%) | 18/20 (90%) | 20/20 (100%) | 20310 |
| `z-ai/glm-4.7-flash:nitro` | `default` | 9/20 (45%) | 7/20 (35%) | 8/20 (40%) | 12939 |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` | 13/20 (65%) | 8/20 (40%) | 8/20 (40%) | 14786 |
| `z-ai/glm-4.7:nitro` | `default` | 20/20 (100%) | 20/20 (100%) | 20/20 (100%) | 15228 |
| `z-ai/glm-4.7:nitro` | `glm_4_7_recommended` | 20/20 (100%) | 20/20 (100%) | 17/20 (85%) | 19204 |

Notable observations:
- `long_arguments_guard` is the main reliability bottleneck in this snapshot (~72% across strategies).
  It exercises `max_tool_args_bytes` (`ARGUMENTS_TOO_LARGE`) and requires the model to retry with a shorter payload.
- “Raw” vs “production” deltas were smaller than expected on tool scenarios (~88% vs ~87%).
  - Production removed `NO_TOOL_USE_ENDPOINT` errors (provider capability mismatches), but had more `ASSERTION_FAILED`.
  - Treat these strategy differences as a prompt/harness signal; real production flows do not require final text to be exactly `"Done."`.
- Model-level notes:
  - Avoid `minimax/minimax-m2-her` for tool calling in this harness (0% tool scenario success).
  - `z-ai/glm-4.7-flash` remained weak for tool calling (40–65% depending on profile).

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
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` (no overrides) | `deepseek_openrouter_compat` | Yes | 95% tool success in this snapshot. |
| `deepseek/deepseek-v3.2:nitro` | `default` / `deepseek_v3_2_local_recommended` | `deepseek_openrouter_compat` | Conditional | Tool success varied by sampling profile (75–95%); misses were concentrated in `long_arguments_guard`. |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` (t=1.5) | `gemini_openrouter_compat` | Yes | `gemini_2_5_flash_creative` was 100%; `default` had one tool-scenario miss (95%) in this snapshot. |
| `google/gemini-3-flash-preview:nitro` | `default` (no overrides) | `gemini_openrouter_compat` | Yes | 95% tool success in this snapshot. |
| `google/gemini-3-pro-preview:nitro` | `default` (no overrides) | `gemini_openrouter_compat` | Conditional | 80% tool success in this snapshot; misses were concentrated in `long_arguments_guard`. |
| `moonshotai/kimi-k2.5:nitro` | `default` (no overrides) | - | Yes (tool scenarios) | Tool scenarios were 100%, but the strict `chat_only` control prompt was brittle. |
| `openai/gpt-5.2:nitro` | `default` (no overrides) | - | Yes | 100% tool scenarios in this snapshot. |
| `openai/gpt-5.2-chat:nitro` | `default` (no overrides) | - | Yes (tool scenarios) | 100% tool scenarios in this snapshot (control prompt still brittle on some routes). |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` (no overrides) | `content_tag_tool_call_fallback` | Yes | `qwen_recommended` hurt tool calling here; prefer `default`. |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `qwen_recommended` (t=0.7 top_p=0.8 top_k=20 min_p=0) | - | Yes | 100% tool scenarios across both profiles in this snapshot. |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `qwen_recommended` (t=0.7 top_p=0.8 top_k=20 min_p=0) | - | Yes | 100% tool scenarios across both profiles in this snapshot. |
| `x-ai/grok-4.1-fast` | `grok_default` (t=0.3) | - | Conditional | Tool scenarios were strong (up to 100% depending on profile), but provider-level 403s and strict control brittleness still appeared. |
| `z-ai/glm-4.7:nitro` | `default` (no overrides) | `content_tag_tool_call_fallback` | Yes | `default` was 100%; `glm_4_7_recommended` regressed under production workarounds in this snapshot (85%). |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` (t=0.7 top_p=1.0) | `content_tag_tool_call_fallback` | No (for tool calling) | ~40% tool success in this snapshot. |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` (t=1.0 top_p=0.95 top_k=40) | `content_tag_tool_call_fallback` | No (for tool calling) | `NO_TOOL_CALLS` + `long_arguments_guard` failures dominated in this snapshot. |
| `minimax/minimax-m2-her` | `default` (no overrides) | `tool_use_disabled` | No (for tool calling) | Tool use disabled (capability mismatch for this harness). |
