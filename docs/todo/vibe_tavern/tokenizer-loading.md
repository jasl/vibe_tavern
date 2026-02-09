# TODO: Tokenizer Loading for Accurate Token Estimation (Plan)

Goal: improve token estimation/trimming accuracy across **multi-provider** and
OpenAI-compatible model endpoints by selecting/loading the correct tokenizer per
model (or model family).

This is a separate backlog item from native multilingual support. It affects
prompt trimming/budgeting correctness and reliability, but it is not required
to ship `runtime[:language_policy]` P0.

## Current state

- Token estimation utility exists:
  - `vendor/tavern_kit/lib/tavern_kit/token_estimator.rb`
- Default path uses `tiktoken_ruby` with:
  - default encoding `cl100k_base`
  - `encoding_for_model(model_hint)` when possible
  - safe fallback to default encoding on errors
- `TokenEstimator` already supports an optional app-owned `registry:`:
  - exact and glob (`File.fnmatch?`) lookups by `model_hint`
  - current P0 supports `tokenizer_family: :heuristic` via
    `chars_per_token:` (keeps hot-path fast + deterministic)

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
- Remaining work is P1+ multi-backend tokenizer loading.

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

## Proposed design (TavernKit-side)

Keep the existing adapter interface and add a **registry + selector**:

1) Registry (app/provider owned; optional):
   - `model_name` → `tokenizer_backend` + optional `tokenizer_resource`
   - Or “family” declaration (preferred):
     - `tokenizer_family: :tiktoken | :sentencepiece | :heuristic`
     - `tokenizer_id:` / `tokenizer_path:` / `fallback_id:` (optional)

2) Selector:
   - Use an explicit registry entry if present.
   - Otherwise:
     - try `tiktoken` with `encoding_for_model`
     - fallback to heuristic `chars_per_token` estimation (configurable per
       family/provider)

3) Adapters (incremental):
   - Keep: `TokenEstimator::Adapter::Tiktoken`
   - Add (P1+):
     - `Adapter::SentencePiece` (local `.model` file)
     - Avoid HF tokenizers unless we find a stable Ruby-native option
   - Consider “provider tokenize endpoint” adapters where available (but do not
     block on it; avoid extra network calls in trimming loops).

## Decisions (current)

- Registry location: app-only.
  - If the app does not provide a registry entry, fallback to:
    `tiktoken` (best effort) → heuristic estimate.
- Minimal registry entry shape (P0):
  - `{ tokenizer_family: :heuristic, chars_per_token: Float }`
- Tokenizer assets: pre-bundled only.
  - Do not download tokenizer assets at runtime.
- Ruby backend recommendation:
  - P0: keep `tiktoken_ruby` + heuristic fallback (fast, low risk).
  - P1 (optional): add SentencePiece support if we can adopt a stable Ruby gem
    and ship `.model` assets with the app.
  - Future direction: HF tokenizers (Rust `tokenizers`) via an app-owned Ruby
    binding (not a P0 requirement); until then, use them only for offline
    calibration/eval scripts.

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

## Development plan (ordered)

P1 (multi-backend tokenizer loading):
1) Add SentencePiece backend support (if we can do it reliably in Ruby).
2) Add optional local tokenizer assets (app-owned) with caching.
3) Add “model family” presets matching common OSS families.

P2 (accuracy guardrails):
1) Add calibration fixtures per family/provider.
2) Enforce conservative safety margins for trimming:
   - e.g. “treat estimate as lower bound; keep headroom”
3) Calibration helper:
   - use `script/llm_token_estimator_sanity.rb` to compare estimates vs provider `usage`

## Acceptance criteria

- For configured models, trimming avoids context-length errors in harness runs.
- Estimation does not regress hot-path latency materially (cache tokenizers).
- For unsupported models, estimator falls back safely and emits trace signals
  (so we can fix config rather than guess).

## Open questions (remaining)

1) If we add SentencePiece (P1, low priority), which Ruby gem do we trust operationally?
   - build/deploy story on Linux (native extension) and dev environments
   - caching lifecycle (process-level singleton vs per-request)
