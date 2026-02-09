# TODO: Tokenizer Loading for Accurate Token Estimation

Goal: improve token estimation/trimming accuracy across **multi-provider** and
OpenAI-compatible model endpoints by selecting/loading the correct tokenizer per
model (or model family).

This is a separate backlog item from native multilingual support. It affects
prompt trimming/budgeting correctness and reliability, but it is not required
to ship `runtime[:language_policy]` P0.

## Current state (done in TavernKit Core)

Implemented in `vendor/tavern_kit/` (platform-agnostic):

- `TavernKit::TokenEstimator` supports a registry-driven backend selector:
  - default: `tiktoken` (best effort) → fallback heuristic (never raise)
  - optional: `:hf_tokenizers` (local `tokenizer.json` via `tokenizers` gem)
  - registry supports exact keys and glob patterns (`File.fnmatch?`)
- Caching:
  - process-level LRU cache for loaded `tokenizer.json`
  - `TokenEstimator#prewarm!` for boot-time preload (Hash registries only)
- Debug tooling:
  - `TavernKit::PromptInspector` with per-message + totals breakdowns

Docs live in:
- `vendor/tavern_kit/docs/core-interface-design.md`
- `vendor/tavern_kit/docs/prompt-inspector.md`

This is good for OpenAI-family models supported by `tiktoken`, but many
non-OpenAI models (and local “OpenAI-compatible” endpoints) do not map cleanly
to a `tiktoken` encoding.

## Where this should live

This capability is **platform-agnostic** (it directly affects trimming/budgeting
and any pipeline that estimates tokens), so implement it in
`vendor/tavern_kit/` (TavernKit Core), and integrate from `lib/tavern_kit/`
(VibeTavern / app-owned providers) by:
- passing a per-app registry into `TavernKit::TokenEstimator.new(registry: ...)`
- setting `ctx[:model_hint]` to a canonical “tokenizer model hint” (family)

Status:

- P0 (registry + model_hint wiring + safe fallbacks) is implemented. Source of
  truth lives in `vendor/tavern_kit/docs/` (Core docs).
- Remaining work is app-side asset curation + registry wiring.

## Why this matters

Token estimation accuracy affects:
- trimming correctness (what gets dropped first under budget)
- safety margins for request size (avoiding context-length errors)
- observability (token budgets in traces)
- (indirectly) multilingual policy stability (small fixed blocks like language
  policy should not be “trimmed away” due to bad estimates)

## Scope and constraints

P0 constraints:
- Deterministic and fast on the request hot path (budgeting/trimming loops).
- Graceful degradation:
  - if a tokenizer cannot be loaded, fallback to a safe estimate
  - never raise from token estimation in production paths
- App/config owned:
  - the app/provider integration should be able to declare “tokenizer family”
    for a given model without guessing from free-form model names.

Non-goals:
- building a full “prompt compression” system
- shipping/maintaining a large tokenizer zoo in `lib/tavern_kit`

## Reference: SillyTavern’s approach

SillyTavern maintains a per-model tokenizer loader with multiple backends:
- SentencePiece models for Llama/Mistral/Yi/Gemma/Jamba families
- “Web tokenizers” (JSON) for families like Claude/Llama3/Qwen2/DeepSeek
- Optional remote downloads + fallback models

See: `resources/SillyTavern/src/endpoints/tokenizers.js`

## Remaining work (VibeTavern app-side)

This is the “small set of popular models” part (≤ ~10 families). We need to:

1) Create canonical model hint normalization:
   - map provider model IDs/variants into a small set of stable hints
     (e.g. `"llama3"`, `"qwen3"`, `"mistral"`)
2) Curate and commit tokenizer assets in-repo (do **not** use `/resources/`):
   - suggested location: `vendor/tokenizers/<family>/tokenizer.json`
3) Wire registry + prewarm during boot:
   - build a registry Hash with glob patterns for variants
   - initialize a long-lived `TavernKit::TokenEstimator.new(registry: ...)`
   - `prewarm!(strict: Rails.env.production?)` so production fails fast on
     missing/misconfigured assets

## Decisions (kept)

- Registry is app-owned (provider integration knows the real model IDs).
- Tokenizer assets are pre-bundled only (no runtime downloads).
- The hot path should stay deterministic and never raise.

Recommended P1 approach (fits “~10 popular models”):

- Maintain a small set of **canonical tokenizer assets** (≤ ~10) committed into
  the Rails app (do **not** put them under `/resources` — it’s gitignored).
  Suggested location: `vendor/tokenizers/<family>/tokenizer.json`
- Implement an app-owned `tokenizer_model_hint(model_id)` that normalizes
  variants (provider suffixes, quantization tags, “nitro”, etc.) into canonical
  hints like `"llama3"`, `"qwen3"`, `"mistral"`.
- Provide a registry mapping canonical hints (and glob variants) to a backend:
  - `{ tokenizer_family: :hf_tokenizers, tokenizer_path: "..." }`
  - fallback: `{ tokenizer_family: :heuristic, chars_per_token: ... }`
- Rely on core process-level LRU caching keyed by `tokenizer_path`.
- Add an app initializer to **prewarm** (load) all configured tokenizers at
  boot, with a strict mode for production deploy validation.

Status: Core support is done; remaining work is app-side asset curation +
registry wiring (no business logic depends on this yet).

Example (app/provider config object):

```ruby
class ProviderConfig
  def tokenizer_model_hint(model_id)
    id = model_id.to_s
    return "qwen2.5" if id.downcase.include?("qwen2.5")
    id
  end

  def tokenizer_registry
    {
      # Canonical family hint (preferred)
      "qwen2.5" => { tokenizer_family: :heuristic, chars_per_token: 3.0 }, # example only; calibrate
      # Optional: glob keys are supported (P0 implementation uses File.fnmatch?)
      "qwen/qwen2.5-*" => { tokenizer_family: :heuristic, chars_per_token: 3.0 }, # example only; calibrate
    }
  end
end
```

Example (P1: HF tokenizer.json mapping + prewarm):

```ruby
# config/initializers/tokenizers.rb
Rails.application.config.after_initialize do
  registry = {
    "qwen3" => {
      tokenizer_family: :hf_tokenizers,
      tokenizer_path: Rails.root.join("vendor/tokenizers/qwen3/tokenizer.json").to_s,
    },
    "qwen/qwen3-*" => {
      tokenizer_family: :hf_tokenizers,
      tokenizer_path: Rails.root.join("vendor/tokenizers/qwen3/tokenizer.json").to_s,
    },
  }

  estimator = TavernKit::TokenEstimator.new(registry: registry)

  # Prewarm loads all configured tokenizer.json once so request hot paths don’t
  # pay the cost. In production, strict mode should fail fast at boot if an
  # expected tokenizer can’t be loaded.
  estimator.prewarm!(strict: Rails.env.production?)

  Rails.application.config.x.vibe_tavern_tokenizer_registry = registry
  Rails.application.config.x.vibe_tavern_token_estimator = estimator
end

# Then, when building a per-request runtime:
#
# runtime[:token_estimation] = {
#   model_hint: ProviderConfig.new.tokenizer_model_hint(model_id),
#   tokenizer_registry: Rails.application.config.x.vibe_tavern_tokenizer_registry,
#   token_estimator: Rails.application.config.x.vibe_tavern_token_estimator,
# }
```

## Remaining checklist (ordered)

P1 (app-side registry + assets):
1) ⏳ Add canonical model hint normalization helpers.
2) ⏳ Add a small seed registry (≤ ~10 families) + glob variants.
3) ⏳ Bundle tokenizer assets under `vendor/tokenizers/`.
4) ⏳ Add a boot-time initializer that prewarms in production.

P2 (accuracy guardrails, optional):
1) Add calibration fixtures per family/provider.
2) Enforce conservative safety margins for trimming (treat estimate as lower bound).
3) Add a calibration script to compare estimates vs provider `usage`.

## Acceptance criteria

- For configured models, trimming avoids context-length errors in harness runs.
- Estimation does not regress hot-path latency materially (cache tokenizers).
- For unsupported models, estimator falls back safely and emits trace signals
  (so we can fix config rather than guess).

## Open questions

1) Licensing/attribution for bundling tokenizer assets.
2) If we add SentencePiece later: which Ruby gem is operationally safe?
