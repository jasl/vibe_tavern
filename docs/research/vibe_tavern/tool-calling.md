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

### Eval strategies (baseline vs production)

The harness supports two strategies:

- `production` (default): applies model-specific workarounds from `ModelCatalog`
  (via `ToolCalling::Presets`), e.g. DeepSeek/Gemini OpenRouter compatibility or
  content-tag fallback for weaker tool-call emitters.
- `baseline`: disables model-specific workarounds (provider defaults + generic
  normalization only), to quantify how much the workarounds matter.

Env:
- `OPENROUTER_STRATEGY_FILTER=production` (default), or `baseline,production`
- `OPENROUTER_STRATEGY_MATRIX=1` (run all strategies)

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

Model/profile matrix (tool scenarios only):

Note:
- Each model/profile has 50 runs total: 40 “tool scenarios” + 10 control runs (`chat_only`).
- Use `tool_ok_rate` for tool-calling reliability; `chat_only` is a strict prompt-adherence control.

| model | sampling_profile | tool_ok | tool_ok_rate | control_ok (chat_only) | p95_ms | top tool failures |
|---|---|---:|---:|---:|---:|---|
| `anthropic/claude-opus-4.6:nitro` | `default` | 40/40 | 100.0% | 10/10 | 18392 | - |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` | 27/40 | 67.5% | 10/10 | 12553 | missing_workspace_id x4; type_error_recovery x4; ASSERTION_FAILED x8 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_creative_writing` | 33/40 | 82.5% | 6/10 | 23135 | long_arguments_guard x3; happy_path x2; ASSERTION_FAILED x7 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_general_conversation` | 34/40 | 85.0% | 10/10 | 20519 | long_arguments_guard x5; type_error_recovery x1; ASSERTION_FAILED x5 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_local_recommended` | 36/40 | 90.0% | 10/10 | 22435 | long_arguments_guard x4; ASSERTION_FAILED x4 |
| `deepseek/deepseek-v3.2:nitro` | `default` | 36/40 | 90.0% | 10/10 | 22886 | long_arguments_guard x4; ASSERTION_FAILED x4 |
| `google/gemini-2.5-flash:nitro` | `default` | 39/40 | 97.5% | 10/10 | 12765 | type_error_recovery x1; TOOL_ERROR x1 |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` | 40/40 | 100.0% | 10/10 | 12633 | - |
| `google/gemini-3-flash-preview:nitro` | `default` | 38/40 | 95.0% | 10/10 | 10682 | long_arguments_guard x2; ASSERTION_FAILED x2 |
| `google/gemini-3-pro-preview:nitro` | `default` | 30/40 | 75.0% | 5/10 | 21059 | long_arguments_guard x9; happy_path x1; ASSERTION_FAILED x10 |
| `minimax/minimax-m2-her` | `default` | 0/40 | 0.0% | 5/10 | 26602 | happy_path x10; long_arguments_guard x10; ASSERTION_FAILED x40 |
| `minimax/minimax-m2.1:nitro` | `default` | 32/40 | 80.0% | 9/10 | 21621 | long_arguments_guard x8; NO_TOOL_CALLS x6 |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` | 34/40 | 85.0% | 7/10 | 20131 | long_arguments_guard x6; NO_TOOL_CALLS x5 |
| `moonshotai/kimi-k2.5:nitro` | `default` | 40/40 | 100.0% | 0/10 | 19829 | - |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` | 40/40 | 100.0% | 0/10 | 19368 | - |
| `openai/gpt-5.2-chat:nitro` | `default` | 40/40 | 100.0% | 0/10 | 15249 | - |
| `openai/gpt-5.2:nitro` | `default` | 39/40 | 97.5% | 10/10 | 13240 | long_arguments_guard x1; ASSERTION_FAILED x1 |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` | 40/40 | 100.0% | 10/10 | 9131 | - |
| `qwen/qwen3-235b-a22b-2507:nitro` | `qwen_recommended` | 30/40 | 75.0% | 10/10 | 8028 | long_arguments_guard x10; ASSERTION_FAILED x10 |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` | 40/40 | 100.0% | 10/10 | 13206 | - |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `qwen_recommended` | 40/40 | 100.0% | 10/10 | 12059 | - |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` | 40/40 | 100.0% | 10/10 | 12179 | - |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `qwen_recommended` | 40/40 | 100.0% | 10/10 | 8718 | - |
| `x-ai/grok-4.1-fast` | `default` | 37/40 | 92.5% | 4/10 | 125091 | long_arguments_guard x3; TIMEOUT x3 |
| `x-ai/grok-4.1-fast` | `grok_default` | 35/40 | 87.5% | 5/10 | 125504 | long_arguments_guard x5; TIMEOUT x3 |
| `z-ai/glm-4.7-flash:nitro` | `default` | 21/40 | 52.5% | 2/10 | 19081 | type_error_recovery x9; long_arguments_guard x7; ASSERTION_FAILED x18 |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` | 21/40 | 52.5% | 2/10 | 26568 | type_error_recovery x10; long_arguments_guard x7; ASSERTION_FAILED x19 |
| `z-ai/glm-4.7:nitro` | `default` | 40/40 | 100.0% | 0/10 | 10938 | - |
| `z-ai/glm-4.7:nitro` | `glm_4_7_recommended` | 40/40 | 100.0% | 1/10 | 11491 | - |

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
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` (no overrides) | `deepseek_openrouter_compat` | No (for tool calling) | Low tool success rate (67.5%) in this snapshot. |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_local_recommended` (t=1.0 top_p=0.95) | `deepseek_openrouter_compat` | Conditional | ~90% tool success; main bottleneck was `long_arguments_guard`. |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` (t=1.5) | `gemini_openrouter_compat` | Yes | 100% tool scenarios in this snapshot (creative profile). |
| `google/gemini-3-flash-preview:nitro` | `default` (no overrides) | `gemini_openrouter_compat` | Conditional | 95% tool success; misses were `long_arguments_guard`. |
| `google/gemini-3-pro-preview:nitro` | `default` (no overrides) | `gemini_openrouter_compat` | No (for tool calling) | 75% tool success in this snapshot. |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` (t=0.6 top_p=0.95) | - | Yes (tool scenarios) | Tool scenarios were 100%, but the strict `chat_only` control prompt was brittle. |
| `openai/gpt-5.2:nitro` | `default` (no overrides) | - | Yes | 97.5% tool success in this snapshot. |
| `openai/gpt-5.2-chat:nitro` | `default` (no overrides) | - | Yes (tool scenarios) | Tool scenarios were 100%, but the strict `chat_only` control prompt was brittle. |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` (no overrides) | `content_tag_tool_call_fallback` | Yes | `qwen_recommended` hurt tool calling here; prefer `default`. |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `qwen_recommended` (t=0.7 top_p=0.8 top_k=20 min_p=0) | - | Yes | 100% tool scenarios across both profiles in this snapshot. |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `qwen_recommended` (t=0.7 top_p=0.8 top_k=20 min_p=0) | - | Yes | 100% tool scenarios across both profiles in this snapshot. |
| `x-ai/grok-4.1-fast` | `grok_default` (t=0.3) | - | Conditional | Timeouts were the dominant failure mode here (p95 ~125s). |
| `z-ai/glm-4.7:nitro` | `default` (no overrides) | `content_tag_tool_call_fallback` | Yes (tool scenarios) | Tool scenarios were 100%, but the strict `chat_only` control prompt was brittle. |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` (t=0.7 top_p=1.0) | `content_tag_tool_call_fallback` | No (for tool calling) | 52.5% tool success in this snapshot. |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` (t=1.0 top_p=0.95 top_k=40) | `content_tag_tool_call_fallback` | No (for tool calling) | `NO_TOOL_CALLS` + `long_arguments_guard` failures dominated in this snapshot. |
| `minimax/minimax-m2-her` | `default` (no overrides) | `tool_use_disabled` | No (for tool calling) | Tool use disabled (capability mismatch for this harness). |
