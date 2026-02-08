# Structured Directives (Research / Reliability Case Study)

This document describes the **Structured Directives** experiment: a structured
output envelope that can drive UI/state without invoking tools.

Directives are **not tool calls**. They are **UI/state instructions** emitted by
the model as structured output, intended to be:

- single-round when possible (faster, fewer failure points)
- deterministic to parse (contract tests + eval harness)
- provider/model tolerant (fallback modes + error classification)

Out of scope (for now):
- agent-driven character / lorebook generation workflows (deferred; no final tech route yet)
  - see `docs/todo/vibe_tavern/deferred-agentic-generation.md`

Scope:
- OpenAI-compatible APIs (OpenAI / OpenRouter / VolcanoEngine)
- output is a JSON "envelope" (assistant_text + directives[])
- directives do **not** perform I/O or side effects (no network/files/DB)

Non-goals (for now):
- shipping UI implementation (this is protocol + runner behavior only)
- model-specific hacks in core runners (quirks live in opt-in presets/transforms)

Related (separate protocol):
- Tool calling (multi-turn, side effects): `docs/research/vibe_tavern/tool-calling.md`
- Architecture overview: `docs/research/vibe_tavern/architecture.md`

## Conclusions (current)

- Prefer `json_schema` (then `json_object`) for reliability; treat `prompt_only` as a last resort.
- The most common “real” failure mode is **valid JSON but wrong directive semantics**
  (e.g. missing a required `ui.request_upload`), not JSON parsing.
- Production strategy: enable **semantic repair** when a specific directive is required.
  This trades a small number of extra round-trips for a large reliability gain.
- Provider routing matters (especially on OpenRouter): some model + parameter sets can
  yield **HTTP 404 for structured modes** (“no endpoints support the requested parameters”).
  When this happens, either:
  - keep structured-mode sampling params minimal (avoid exotic knobs), or
  - start from `json_object` / `prompt_only` for that path to avoid repeated 404s.
- Compared to multi-turn tool calling, directives are easier to make reliable (fewer round-trips).
  In our current sampling-matrix snapshots, tool-calling “tool scenarios” were ~84–87% across strategies
  (`raw`/`baseline`/`production`), while directives were ~98–99% overall.

## Eval snapshot (OpenRouter, all models, sampling matrix)

Snapshot: 2026-02-08 (OpenRouter), 17 models, 4 scenarios, 5 trials per model/profile/strategy.

Command:

```sh
OPENROUTER_API_KEY=... OPENROUTER_JOBS=2 OPENROUTER_TRIALS=5 OPENROUTER_MODEL_FILTER=all \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  OPENROUTER_STRATEGY_FILTER="raw,baseline,production" \
  bundle exec ruby script/llm_directives_eval.rb
```

Strategy summary:

| strategy | ok | p50_ms | p95_ms | multi-attempt | had_http_404 | had_semantic_error |
|---|---:|---:|---:|---:|---:|---:|
| `raw` | 567/580 (98%) | 2700 | 6928 | 11% | 0% | 0% |
| `baseline` | 572/580 (99%) | 2654 | 7962 | 9% | 7% | 0% |
| `production` | 575/580 (99%) | 2752 | 7222 | 9% | 7% | 2% |

By scenario (ok / runs):

| scenario | `raw` | `baseline` | `production` |
|---|---:|---:|---:|
| `show_form` | 144/145 (99%) | 145/145 (100%) | 144/145 (99%) |
| `toast` | 140/145 (97%) | 142/145 (98%) | 144/145 (99%) |
| `patch_draft` | 143/145 (99%) | 145/145 (100%) | 144/145 (99%) |
| `request_upload` | 140/145 (97%) | 140/145 (97%) | 143/145 (99%) |

Production best-per-model (choose best sampling profile per model):

| model | profile | mode | ok (prod) | p95_ms | recommended? | notes |
|---|---|---|---:|---:|---|---|
| `anthropic/claude-opus-4.6:nitro` | `default` | `json_object` | 20/20 (100%) | 3645 | Yes | `json_schema` is unreliable on OpenRouter for this route. |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` | `json_schema` | 20/20 (100%) | 2859 | Yes | - |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_local_recommended` | `json_schema` | 20/20 (100%) | 5691 | Yes | Avoid creative/conversation profiles for directives (slow in this snapshot). |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` | `json_schema` | 20/20 (100%) | 2903 | Yes | `default` was also 20/20. |
| `google/gemini-3-flash-preview:nitro` | `default` | `json_schema` | 20/20 (100%) | 2641 | Yes | - |
| `google/gemini-3-pro-preview:nitro` | `default` | `json_schema` | 20/20 (100%) | 5768 | Yes | - |
| `minimax/minimax-m2-her` | `default` | `prompt_only` | 17/20 (85%) | 16845 | No | Weak semantics adherence in this harness. |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` | `prompt_only` | 20/20 (100%) | 10375 | Yes | - |
| `moonshotai/kimi-k2.5:nitro` | `default` | `json_schema` | 20/20 (100%) | 6048 | Yes | - |
| `openai/gpt-5.2-chat:nitro` | `default` | `prompt_only` | 20/20 (100%) | 3972 | Yes | OpenRouter structured modes were not stable here. |
| `openai/gpt-5.2:nitro` | `default` | `prompt_only` | 20/20 (100%) | 3296 | Yes | OpenRouter structured modes were not stable here. |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` | `json_schema` | 20/20 (100%) | 2082 | Yes | - |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` | `json_schema` | 20/20 (100%) | 2709 | Yes | `qwen_recommended` triggered consistent OpenRouter 404s in structured modes. |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` | `json_schema` | 20/20 (100%) | 3118 | Yes | `qwen_recommended` triggered consistent OpenRouter 404s in structured modes. |
| `x-ai/grok-4.1-fast` | `grok_default` | `json_schema` | 20/20 (100%) | 5078 | Yes | - |
| `z-ai/glm-4.7-flash:nitro` | `default` | `json_schema` | 20/20 (100%) | 10415 | Yes | - |
| `z-ai/glm-4.7:nitro` | `glm_4_7_recommended` | `json_schema` | 20/20 (100%) | 13582 | Yes | - |

## Benchmark: Tool calling (raw/baseline/production)

This is not an apples-to-apples comparison (different scenarios), but it is a useful baseline:
multi-turn tool calling tends to have more failure points than single-turn directives.

Tool calling snapshot command:

```sh
OPENROUTER_TRIALS=5 OPENROUTER_MODEL_FILTER=all \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  OPENROUTER_STRATEGY_FILTER="raw,baseline,production" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

Tool calling summary (tool scenarios only):

| strategy | tool scenarios only | tool p50_ms | tool p95_ms |
|---|---:|---:|---:|
| `raw` | 496/580 (86%) | 8605 | 20366 |
| `baseline` | 487/580 (84%) | 8113 | 19592 |
| `production` | 503/580 (87%) | 8241 | 20636 |

Hardest tool-calling scenario in this snapshot was `long_arguments_guard` (~70–74% across strategies).

## Failure modes (what we see in practice)

Structured directives are single-turn, but they still fail in characteristic ways:

- **Capability gaps**:
  - not every provider/model route supports `response_format: { type: "json_schema" }`
  - some support `json_object` but not `json_schema`
- **Valid JSON, wrong semantics**:
  - the envelope parses, but the directive list is empty or missing a required `type`
- **Prompt-only brittleness**:
  - when `response_format` is unavailable, success depends entirely on prompt adherence
- **Truncation / length**:
  - even in structured modes, responses can be cut off (invalid JSON or missing fields)

The core approach: keep the schema simple, parse tolerantly, validate strictly,
and use a fallback ladder (`json_schema` → `json_object` → `prompt_only`) with
optional **semantic repair** when a specific directive is required.

## Protocol: Envelope

The model returns a single JSON object:

```json
{
  "assistant_text": "Human-readable response text.",
  "directives": [
    { "type": "ui.show_form", "payload": { "form_id": "example_form_v1" } }
  ]
}
```

Rules:
- `assistant_text` is always present (string, may be empty).
- `directives` is always present (array, may be empty).
- Each directive is an object with:
  - `type` (string)
  - `payload` (object)
- Unknown fields are allowed inside `payload` (schema stays simple; Ruby validator enforces shape).

## Directive Types

Directive `type` strings are application-defined.

The infrastructure (`lib/tavern_kit/vibe_tavern`) does **not** hardcode the set
of directive types; the app injects an allowlist (similar to how tools are
injected via `ToolRegistry`).

Recommended canonical naming is **dot-namespaced** for readability (examples):

- `ui.show_form`
  - payload: `{ "form_id": String, ... }`
- `ui.toast`
  - payload: `{ "message": String, "level": "info"|"success"|"warning"|"error" (optional), ... }`
- `ui.patch`
  - payload: `{ "ops": Array<PatchOp>, ... }`
- `ui.request_upload`
  - payload: `{ "purpose": String, "accept": Array<String> (optional), "max_bytes": Integer (optional), ... }`

### Naming reliability

When the app injects an allowlist, the validator can canonicalize superficial
variants (e.g. `ui_show_form`, `ui-show-form`) to the canonical form.

For semantic aliases (e.g. mapping `show_form` to `ui.show_form`), inject an
explicit alias map.

## Patch Semantics: `ui.patch`

We use a small, LLM-friendly patch format (similar to the tool-call eval
workspace ops), instead of full RFC6902 JSON Patch.

`PatchOp` shape:

```json
{ "op": "set", "path": "/draft/foo", "value": "bar" }
```

Supported ops:
- `set`: set `value` at `path`
- `delete`: delete key/element at `path`
- `append`: append `value` to array at `path` (creates array if missing)
- `insert`: insert `value` into array at `path` at `index`

Normalization:
- Some models naturally emit RFC6902-style ops (`add`, `replace`, `remove`, `push`).
- The helper `TavernKit::VibeTavern::Directives::Validator.normalize_patch_ops(...)`
  canonicalizes them to the ops above (`set`, `delete`, `append`).
- Tolerance:
  - If `op` is missing/blank, it is inferred:
    - `value` present -> `set`
    - otherwise -> `delete`
  - If `path` does not start with `/`, it is normalized to `/draft/<path>` (or `/<path>` when it starts with `draft/` or `ui_state/`).
  - `ops` may be provided as a single object (it will be wrapped into an array).

Path rules:
- must start with `/draft/` or `/ui_state/`

Payload validation is application-defined. The infrastructure provides a helper
`TavernKit::VibeTavern::Directives::Validator.validate_patch_ops(...)` that app
code can use inside an injected payload validator.

## Runner Strategy (Single request, with fallbacks)

Primary: Structured Outputs (JSON Schema)
- Request uses `response_format: { type: "json_schema", json_schema: { strict: true, schema: ... } }`.
- This gives the highest rate of correct `type` strings when you inject an allowlist (enum constrained).

Fallbacks (when unsupported or invalid output):
1) JSON mode (`response_format: { type: "json_object" }`) + prompt instructions.
2) Prompt-only JSON (no `response_format`) + prompt instructions + tolerant parsing.
3) Optional repair retry: if parsing/validation fails, retry once with a strict
   "fix the JSON only" instruction including the error category (truncated).
4) Optional semantic repair (app-injected): if the envelope is valid but does not
   satisfy a caller-defined requirement (e.g. missing a required directive type),
   treat it as invalid and retry/fallback.

Key requirement: **flow continues**.
- Runners do not crash on invalid JSON; they return categorized errors and either:
  - empty `directives` with a best-effort `assistant_text`, or
  - a failure result with details so the caller can fall back to plain chat/tool use.
- Invalid directives inside an otherwise valid envelope are dropped and reported as warnings.

## Implementation Components

Code lives under `lib/tavern_kit/vibe_tavern/`:

- `TavernKit::VibeTavern::Directives::Registry`
  - holds the app-injected directive allowlist + optional aliases + instructions
- `TavernKit::VibeTavern::Directives::Schema`
  - builds the `response_format` hash and JSON schema (kept intentionally simple)
  - takes injected directive types (to build the `type` enum when provided)
- `TavernKit::VibeTavern::Directives::Parser`
  - extracts JSON from assistant content (handles code fences / surrounding text)
  - enforces size limits and returns categorized errors
- `TavernKit::VibeTavern::Directives::Validator`
  - validates required fields and (optionally) enforces an allowlist
  - canonicalizes directive types using injected allowlist + aliases
  - supports app-injected payload validation; includes helper `validate_patch_ops`
- `TavernKit::VibeTavern::PromptRunner`
  - optional `structured_output: :directives_v1` request injection + parse result fields
- `TavernKit::VibeTavern::Directives::Runner`
  - implements json_schema/json_object/prompt-only fallback and optional repair retry

## App Injection (Recommended)

Inject directive definitions (allowlist + aliases) from the app layer:

```ruby
registry =
  TavernKit::VibeTavern::Directives::Registry.new(
    definitions: [
      { type: "ui.show_form", description: "payload: {form_id:String}", aliases: %w[show_form] },
      { type: "ui.toast", description: "payload: {message:String}", aliases: %w[toast] },
    ],
  )

payload_validator =
  lambda do |type, payload|
    case type
    when "ui.show_form"
      { code: "MISSING_FORM_ID" } if payload.fetch("form_id", "").to_s.strip.empty?
    end
  end

# Optional: use EasyTalk models for payload validation (more maintainable).
#
# This keeps the payload contract in one place and provides structured errors.
#
# class ShowFormPayload
#   include EasyTalk::Model
#   define_schema { property :form_id, String, min_length: 1 }
# end
#
# payload_validator =
#   TavernKit::VibeTavern::Directives::PayloadValidators.easy_talk(
#     "ui.show_form" => ShowFormPayload,
#     error_format: :json_pointer,
#   )

structured_output_options = {
  registry: registry,
  allowed_types: registry.types,
  type_aliases: registry.type_aliases,
  payload_validator: payload_validator,
}
```

Optional `structured_output_options` keys:
- `max_bytes`: content size guardrail for parsing
- `schema_name`: override the structured output schema name
- `output_instructions`: extra system instructions about directive types/payloads
- `inject_response_format`: set `false` to disable auto-injection in `PromptRunner` (advanced)

Then use either:
- `PromptRunner` (single request boundary), or
- `Directives::Runner` (includes fallback + repair retry)

Optional semantic validation (recommended when the UI flow requires a specific directive):

```ruby
requires_upload =
  lambda do |result|
    dirs = Array(result[:directives])
    dirs.any? { |d| d["type"] == "ui.request_upload" } ? [] : ["missing ui.request_upload"]
  end

result =
  runner.run(
    system: system,
    history: history,
    structured_output_options: structured_output_options,
    result_validator: requires_upload,
  )
```

## Presets (Provider/Model)

Optional preset helpers exist in `TavernKit::VibeTavern::Directives::Presets`.

The preset hash is intended to be stored on your **LLM provider configuration**
so you can keep provider/model quirks explicit and testable.

Examples:

- Provider defaults (OpenRouter):

```ruby
preset = TavernKit::VibeTavern::Directives::Presets.provider_defaults("openrouter")
```

Notes:
- When enabled, `provider.require_parameters=true` is applied only for structured
  modes (`json_schema` / `json_object`).
- In `prompt_only` fallback mode, the preset forces `provider.require_parameters=false`
  to avoid OpenRouter provider capability-metadata false negatives.
- To avoid cross-protocol leakage when you also use tool calling, directives runner
  ignores request override keys `tools`, `tool_choice`, and `response_format`.

- Build a runner with a preset:

```ruby
runner =
  TavernKit::VibeTavern::Directives::Runner.build(
    client: client,
    model: model,
    preset: preset,
  )
```

If you also want to pin common request overrides on the provider itself:

```ruby
prompt_runner =
  TavernKit::VibeTavern::PromptRunner.new(
    client: client,
    model: model,
    llm_options_defaults: { temperature: 0.7 },
  )
```

You can further compose presets (default + provider + model workarounds) via:

```ruby
combined =
  TavernKit::VibeTavern::Directives::Presets.merge(
    TavernKit::VibeTavern::Directives::Presets.default_directives,
    preset,
    TavernKit::VibeTavern::Directives::Presets.directives(modes: [:prompt_only]),
  )
```

## Testing & Eval

CI tests:
- deterministic adapter-based tests for parser/validator and PromptRunner integration

Live eval (optional):
  - `script/llm_directives_eval.rb` (OpenRouter) to build a model/provider capability matrix
    and track parse/schema success rate + latency percentiles.
    - Quick start (full preset, runs both tool calling + directives):
      - `OPENROUTER_API_KEY=... bundle exec ruby script/llm_vibe_tavern_eval.rb`
    - Full matrix (directives only): `OPENROUTER_API_KEY=... OPENROUTER_EVAL_PRESET=full bundle exec ruby script/llm_directives_eval.rb`
    - Outputs `summary.json`, `summary_by_scenario.json`, and `summary_by_scenario_and_strategy.json` under `tmp/llm_directives_eval_reports/<timestamp>/`.
    - Scenario selection:
      - `OPENROUTER_SCENARIOS=default` (all scenarios)
      - `OPENROUTER_SCENARIOS=simple|typical|extreme` (predefined groups)
	    - Strategy selection:
	      - Baseline vs production-tuned in one run: `OPENROUTER_STRATEGY_FILTER=baseline,production` (or `OPENROUTER_STRATEGY_MATRIX=1`)
	      - “Raw” control group (no provider defaults, no model workarounds, no repair retries): `OPENROUTER_STRATEGY_FILTER=raw`
	      - Full set (incl. raw): `OPENROUTER_STRATEGY_FILTER=raw,baseline,production`
	      - Shorthand (single strategy): `OPENROUTER_SEMANTIC_REPAIR=1` (production)
    - Sampling params are driven by **sampling profiles** (matrix-friendly).
      - By default, the script uses `OPENROUTER_SAMPLING_PROFILE_FILTER=default` (no temperature/top_p override).
      - Profiles are defined in `script/openrouter_sampling_profiles.rb`.
      - Applicability is enforced by default: profiles only run on matching models (`OPENROUTER_SAMPLING_PROFILE_ENFORCE_APPLICABILITY=1`).
      - Optional global overrides:
      - `OPENROUTER_LLM_OPTIONS_DEFAULTS_JSON='{\"temperature\":1.0,\"top_p\":0.95}'`
      - `OPENROUTER_TEMPERATURE=...` / `OPENROUTER_TOP_P=...` / `OPENROUTER_TOP_K=...` / `OPENROUTER_MIN_P=...`
    - Optional semantic repair (higher success, extra round-trips on misses):
      - `OPENROUTER_SEMANTIC_REPAIR=1`

### Eval snapshot (OpenRouter, all models, sampling matrix)

Raw report JSON files are written under `tmp/llm_directives_eval_reports/<timestamp>/`
and are not committed. The tables below are a captured snapshot for reference.

Command:

```sh
OPENROUTER_TRIALS=10 OPENROUTER_MODEL_FILTER=all \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  bundle exec ruby script/llm_directives_eval.rb
```

Summary:
- Overall: `1149/1160` ok (`99.05%`)
- By scenario (ok / runs):
  - `show_form`: `290/290` (`100%`)
  - `toast`: `289/290` (`99.66%`)
  - `patch_draft`: `290/290` (`100%`)
  - `request_upload`: `280/290` (`96.55%`) (hardest)
- By mode (ok_rate):
  - `json_schema`: `835/839` (`99.52%`)
  - `json_object`: `81/81` (`100%`)
  - `prompt_only`: `233/240` (`97.08%`)

Notable observations:
- `prompt_only` remains the weakest mode (expected): when a provider/model cannot reliably support `response_format`, success depends entirely on prompt adherence. Prefer models/providers that can stay on `json_schema`/`json_object`.
- The highest-frequency failure pattern was missing `ui.request_upload` (10/290 `request_upload` runs). Prompt-only runs often return `ui.show_form` to drive an upload flow instead; even `json_schema` runs can occasionally return empty directives or the wrong directive type. If upload UI is critical, treat this as a model-selection gate or add a higher-level reprompt/fallback policy.
- Patch stability was strong in this snapshot (`patch_draft` 100%), helped by patch op/path normalization and the eval harness’ payload normalization into `payload.ops`.
- Sampling profile impact (in this snapshot):
  - DeepSeek V3.2: `default` / `deepseek_v3_2_local_recommended` / `deepseek_v3_2_general_conversation` were 100%; `deepseek_v3_2_creative_writing` had one empty `directives` for `toast`.
  - MiniMax M2.x (prompt-only): `minimax_m2_1_recommended` improved over `default`, but both remained < 100% on `request_upload`.
  - GLM: `z-ai/glm-4.7` was 100% on `glm_4_7_recommended` but not on `default` (one truncated `request_upload` response dropped as invalid). `z-ai/glm-4.7-flash` was 100% on `glm_4_7_flash_tool_calling` but not on `default`.

Model/profile matrix (baseline):

| model | profile | ok | ok_rate | modes (final) | failures |
|---|---|---:|---:|---|---|
| `anthropic/claude-opus-4.6:nitro` | `default` | 40/40 | 100.0% | json_object:40 | - |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_creative_writing` | 39/40 | 97.5% | json_schema:40 | toast: ASSERTION_FAILED: missing ui.toast |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_general_conversation` | 40/40 | 100.0% | json_schema:40 | - |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_local_recommended` | 40/40 | 100.0% | json_schema:40 | - |
| `deepseek/deepseek-v3.2:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `google/gemini-2.5-flash:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` | 40/40 | 100.0% | json_schema:40 | - |
| `google/gemini-3-flash-preview:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `google/gemini-3-pro-preview:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `minimax/minimax-m2-her` | `default` | 37/40 | 92.5% | prompt_only:40 | request_upload: ASSERTION_FAILED: missing ui.request_upload x3 |
| `minimax/minimax-m2.1:nitro` | `default` | 37/40 | 92.5% | prompt_only:40 | request_upload: ASSERTION_FAILED: missing ui.request_upload x3 |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` | 39/40 | 97.5% | prompt_only:40 | request_upload: ASSERTION_FAILED: missing ui.request_upload |
| `moonshotai/kimi-k2.5:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` | 40/40 | 100.0% | json_schema:39 json_object:1 | - |
| `openai/gpt-5.2-chat:nitro` | `default` | 40/40 | 100.0% | prompt_only:40 | - |
| `openai/gpt-5.2:nitro` | `default` | 40/40 | 100.0% | prompt_only:40 | - |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `qwen/qwen3-235b-a22b-2507:nitro` | `qwen_recommended` | 40/40 | 100.0% | json_schema:40 | - |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `qwen_recommended` | 40/40 | 100.0% | prompt_only:40 | - |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `qwen_recommended` | 40/40 | 100.0% | json_object:40 | - |
| `x-ai/grok-4.1-fast` | `default` | 40/40 | 100.0% | json_schema:40 | - |
| `x-ai/grok-4.1-fast` | `grok_default` | 40/40 | 100.0% | json_schema:40 | - |
| `z-ai/glm-4.7-flash:nitro` | `default` | 38/40 | 95.0% | json_schema:40 | request_upload: ASSERTION_FAILED: missing ui.request_upload x2 |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` | 40/40 | 100.0% | json_schema:40 | - |
| `z-ai/glm-4.7:nitro` | `default` | 39/40 | 97.5% | json_schema:40 | request_upload: ASSERTION_FAILED: missing ui.request_upload |
| `z-ai/glm-4.7:nitro` | `glm_4_7_recommended` | 40/40 | 100.0% | json_schema:40 | - |

### Eval snapshot (OpenRouter, all models, sampling matrix, semantic repair enabled)

Raw report JSON files are written under `tmp/llm_directives_eval_reports/<timestamp>/`
and are not committed. The tables below are a captured snapshot for reference.

Command:

```sh
OPENROUTER_TRIALS=10 OPENROUTER_MODEL_FILTER=all \
  OPENROUTER_SAMPLING_PROFILE_FILTER="default,recommended,conversation,creative,tool_calling" \
  OPENROUTER_SEMANTIC_REPAIR=1 \
  bundle exec ruby script/llm_directives_eval.rb
```

Summary:
- Overall: `1160/1160` ok (`100%`)
- By scenario (ok / runs): all `290/290` (`100%`)
- By final mode (runs):
  - `json_schema`: `838`
  - `json_object`: `82`
  - `prompt_only`: `240`
- Repair/overhead signals (runs):
  - `109/1160` (`9.4%`) had more than one attempt (repair retry and/or fallback).
  - `80/1160` (`6.9%`) included an OpenRouter `HTTP 404` in a structured mode (provider routing: “no endpoints found that can handle the requested parameters”).
  - `14/1160` (`1.2%`) required semantic repair (valid envelope, but missing a required directive type; fixed by a retry with explicit feedback).

Notable observations:
- This snapshot reflects a **production-tuned** strategy: when a specific directive is required, semantic repair can recover from “valid JSON, wrong directive” in one additional round-trip.
- “All green” does not mean “all models support json_schema”: some models still rely on `prompt_only` (e.g. OpenAI models on OpenRouter routes) and some profiles can trigger structured routing failures (e.g. Qwen recommended profiles with extra sampling knobs leading to `json_schema` 404 and a fallback).

Model/profile matrix (production strategy):

| model | profile | ok | modes (final) | multi-attempt | http404 | semantic_repair |
|---|---|---:|---|---:|---:|---:|
| `anthropic/claude-opus-4.6:nitro` | `default` | 40/40 | json_object:40 | 0 | 0 | 0 |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_creative_writing` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_general_conversation` | 40/40 | json_schema:40 | 1 | 0 | 1 |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_local_recommended` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `deepseek/deepseek-v3.2:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `google/gemini-2.5-flash:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `google/gemini-2.5-flash:nitro` | `gemini_2_5_flash_creative` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `google/gemini-3-flash-preview:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `google/gemini-3-pro-preview:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `minimax/minimax-m2-her` | `default` | 40/40 | prompt_only:40 | 15 | 0 | 3 |
| `minimax/minimax-m2.1:nitro` | `default` | 40/40 | prompt_only:40 | 4 | 0 | 4 |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` | 40/40 | prompt_only:40 | 3 | 0 | 2 |
| `moonshotai/kimi-k2.5:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` | 40/40 | json_schema:40 | 1 | 0 | 0 |
| `openai/gpt-5.2-chat:nitro` | `default` | 40/40 | prompt_only:40 | 0 | 0 | 0 |
| `openai/gpt-5.2:nitro` | `default` | 40/40 | prompt_only:40 | 0 | 0 | 0 |
| `qwen/qwen3-235b-a22b-2507:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `qwen/qwen3-235b-a22b-2507:nitro` | `qwen_recommended` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `qwen_recommended` | 40/40 | prompt_only:40 | 40 | 40 | 0 |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `qwen_recommended` | 40/40 | json_object:40 | 40 | 40 | 0 |
| `x-ai/grok-4.1-fast` | `default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `x-ai/grok-4.1-fast` | `grok_default` | 40/40 | json_schema:40 | 0 | 0 | 0 |
| `z-ai/glm-4.7-flash:nitro` | `default` | 40/40 | json_schema:39 json_object:1 | 1 | 0 | 0 |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` | 40/40 | json_schema:40 | 1 | 0 | 1 |
| `z-ai/glm-4.7:nitro` | `default` | 40/40 | json_schema:39 json_object:1 | 2 | 0 | 2 |
| `z-ai/glm-4.7:nitro` | `glm_4_7_recommended` | 40/40 | json_schema:40 | 1 | 0 | 1 |

## Production config (directives) and model recommendations

This table is **only** about the directives protocol (not tool calling).

Legend:
- “Preset/workaround” refers to additional `Directives::Presets.directives(...)` overlays.
- Base preset for OpenRouter: `Directives::Presets.provider_defaults("openrouter")`
  (structured modes use `provider.require_parameters=true`, prompt-only uses `false`).
- “-” means “no extra workaround” (keep `Directives::Presets.default_directives`, i.e. `json_schema → json_object → prompt_only`).
- `json_object_first`: `Directives::Presets.directives(modes: %i[json_object prompt_only])`
- `prompt_only`: `Directives::Presets.directives(modes: [:prompt_only])`
- “Semantic repair” refers to the production strategy of supplying a `result_validator` to the directives runner.

| model | recommended sampling profile(s) | preset/workaround | semantic repair | recommended? | notes |
|---|---|---|---|---|---|
| `anthropic/claude-opus-4.6:nitro` | `default` (no overrides) | `json_object_first` | Yes (when required) | Yes | OpenRouter structured routing is more stable starting at `json_object`. |
| `deepseek/deepseek-chat-v3-0324:nitro` | `default` | - | Yes (when required) | Yes | Stable on `json_schema` in this snapshot. |
| `deepseek/deepseek-v3.2:nitro` | `deepseek_v3_2_local_recommended` (t=1.0 top_p=0.95) / `deepseek_v3_2_general_conversation` (t=1.3 top_p=0.95) | - | Yes (when required) | Yes | `deepseek_v3_2_creative_writing` had one miss without semantic repair. |
| `google/gemini-2.5-flash:nitro` | `default` (no overrides) / `gemini_2_5_flash_creative` (t=1.5) | - | Yes (when required) | Yes | Stable on `json_schema` across profiles. |
| `google/gemini-3-flash-preview:nitro` | `default` (no overrides) | - | Yes (when required) | Yes | Stable on `json_schema` in this snapshot. |
| `google/gemini-3-pro-preview:nitro` | `default` (no overrides) | - | Yes (when required) | Yes | Stable on `json_schema` in this snapshot. |
| `moonshotai/kimi-k2.5:nitro` | `kimi_k2_5_instant` (t=0.6 top_p=0.95) | - | Yes (when required) | Yes | Mostly `json_schema`; rare fallback in baseline. |
| `qwen/qwen3-235b-a22b-2507:nitro` | `qwen_recommended` (t=0.7 top_p=0.8 top_k=20 min_p=0) | - | Yes (when required) | Yes | `qwen_recommended` remained compatible with `json_schema` here. |
| `qwen/qwen3-30b-a3b-instruct-2507:nitro` | `default` (no overrides) | - | Yes (when required) | Yes (conditional) | On OpenRouter, `qwen_recommended` (t=0.7 top_p=0.8 top_k=20 min_p=0) caused structured-mode HTTP 404 and fell back to `prompt_only` in 100% of runs. Prefer `default` for directives or strip exotic knobs for structured modes. |
| `qwen/qwen3-next-80b-a3b-instruct:nitro` | `default` (no overrides) | - | Yes (when required) | Yes (conditional) | On OpenRouter, `qwen_recommended` (t=0.7 top_p=0.8 top_k=20 min_p=0) forced `json_object` via `json_schema` 404 in 100% of runs. Prefer `default` for directives (or start at `json_object` for that path). |
| `x-ai/grok-4.1-fast` | `grok_default` (t=0.3) | - | Yes (when required) | Yes | Stable on `json_schema` in this snapshot. |
| `z-ai/glm-4.7:nitro` | `glm_4_7_recommended` (t=1.0 top_p=0.95) | - | Yes (when required) | Yes | `default` had `request_upload` misses without repair. |
| `z-ai/glm-4.7-flash:nitro` | `glm_4_7_flash_tool_calling` (t=0.7 top_p=1.0) | - | Yes (when required) | Yes (conditional) | `default` had `request_upload` misses without repair; prefer the tuned profile. |
| `openai/gpt-5.2:nitro` | `default` (no overrides) | `prompt_only` (OpenRouter) | Yes (when required) | Yes (conditional) | On OpenRouter, structured modes were routed via `prompt_only`. Prefer direct OpenAI API for `json_schema`. |
| `openai/gpt-5.2-chat:nitro` | `default` (no overrides) | `prompt_only` (OpenRouter) | Yes (when required) | Yes (conditional) | Same as above. |
| `minimax/minimax-m2.1:nitro` | `minimax_m2_1_recommended` (t=1.0 top_p=0.95 top_k=40) | `prompt_only` | Yes (when required) | Conditional | Prompt-only + semantic repair can hit 100%, but it costs retries and is inherently less strict than structured modes. |
| `minimax/minimax-m2-her` | `default` (no overrides) | `prompt_only` | Yes (when required) | Conditional | Same caveat as above. |
