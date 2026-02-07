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
  - see `docs/research/vibe_tavern/deferred-agentic-generation.md`

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
    - Outputs `summary.json` and `summary_by_scenario.json` under `tmp/llm_directives_eval_reports/<timestamp>/`.
    - Scenario selection:
      - `OPENROUTER_SCENARIOS=default` (all scenarios)
      - `OPENROUTER_SCENARIOS=simple|typical|extreme` (predefined groups)
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

Run: `tmp/llm_directives_eval_reports/20260207T180246Z`

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

Non-100% model/profile combos in this run:
- `deepseek/deepseek-v3.2:nitro` + `deepseek_v3_2_creative_writing`: `39/40` (missing `ui.toast` x1; returned empty directives)
- `minimax/minimax-m2-her` + `default` (prompt-only): `37/40` (missing `ui.request_upload` x3; returned `ui.show_form`)
- `minimax/minimax-m2.1:nitro` (prompt-only):
  - `default`: `37/40` (missing `ui.request_upload` x3; returned `ui.show_form`)
  - `minimax_m2_1_recommended`: `39/40` (missing `ui.request_upload` x1; returned `ui.show_form`)
- `z-ai/glm-4.7:nitro` + `default`: `39/40` (missing `ui.request_upload` x1; one truncated response dropped as invalid)
- `z-ai/glm-4.7-flash:nitro` + `default`: `38/40` (missing `ui.request_upload` x2; returned `[]` or `ui.toast`)
