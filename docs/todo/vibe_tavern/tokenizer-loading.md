# TODO: Tokenizer Loading + Token Estimator Injection (PromptBuilder)

Goal: make token estimation fast, deterministic, and boring:

- no hot-path downloads
- predictable selection per model hint
- safe fallbacks (never crash request paths)
- explicit injection points in `context` and step config

This document is the actionable “how we run this in production” companion to:

- Research details: `docs/research/vibe_tavern/token-estimation.md`
- Code: `lib/tavern_kit/vibe_tavern/token_estimation.rb`
- Step: `lib/tavern_kit/vibe_tavern/prompt_builder/steps/prepare.rb`
- Core: `vendor/tavern_kit/lib/tavern_kit/token_estimator.rb`

## Selection Strategy (Model Hint -> Backend)

1. Determine `model_hint` for the build.
2. Canonicalize it in the Rails app (`TokenEstimation.canonical_model_hint`).
3. Select a backend entry from the registry:
   - `hf_tokenizers` (local `tokenizer.json`)
   - `tiktoken` (no local asset)
   - `heuristic` (last resort)

Hard constraints:

- Core never downloads tokenizers on demand.
- `estimate(...)` must never raise on external inputs (fallback to tiktoken/heuristic).
- Production should preload local HF tokenizers and fail fast if missing.

## Caching Strategy

There are two layers of caching:

- App-level estimator instance cache:
  - `TavernKit::VibeTavern::TokenEstimation.estimator` memoizes a configured
    `TavernKit::TokenEstimator` per tokenizer root path.
- Core adapter caches:
  - `TokenEstimator` caches HF tokenizers in an LRU cache (by `tokenizer_path`).
  - `tiktoken` adapter caches encoding selection per `model_hint`.

Boot-time preload (recommended):

- In production: `TokenEstimation.estimator.preload!(strict: true)`
- In dev/test: `strict: false` is fine (falls back during execution)

## Failure / Degradation Policy

We treat token estimation as an observability/budget helper, not a correctness boundary.

- Hot path: `TokenEstimator#estimate` rescues failures and falls back:
  - registry adapter -> base adapter (`tiktoken`) -> heuristic -> 0
- Deploy-time: `preload!(strict: true)` is allowed to raise to catch missing assets.

## Injection Points (Context + Step Behavior)

Token estimation is applied in `:prepare` (`PromptBuilder::Steps::Prepare`).

### 1) `context[:token_estimation]` (recommended for PromptRunner runs)

`context[:token_estimation]` is a strict, programmer-owned Hash:

```ruby
context = {
  token_estimation: {
    model_hint: "deepseek/deepseek-chat-v3-0324:nitro",
    # Optional overrides:
    # token_estimator: my_estimator, # responds to #estimate
    # registry: my_registry_hash,
  },
}
```

Behavior:

- If `token_estimation.model_hint` is present and `ctx[:model_hint]` is not set
  (or set blank), `:prepare` sets `ctx[:model_hint]` to the canonical hint.
- If `token_estimation.token_estimator` is provided, it is used as-is.
- Else if `token_estimation.registry` is provided, `:prepare` builds a
  `TavernKit::TokenEstimator.new(registry: registry)`.
- Else, the default `TokenEstimation.estimator` is used.

### 2) `meta(:default_model_hint, ...)` (set by PromptRunner)

`PromptRunner` sets:

- `meta(:default_model_hint, runner_config.model)`

`Prepare` uses this as a fallback input to select `ctx[:model_hint]` when the
context does not specify a model hint.

### 3) Direct state injection (advanced/manual PromptBuilder usage)

If you build a plan directly (not via `PromptRunner`), you can set:

- `token_estimator(...)` on the builder input (wins over context defaults)
- `meta(:model_hint, ...)` (or `meta(:default_model_hint, ...)`) as needed

For PromptRunner runs, prefer `context[:token_estimation]` to keep a single
injection path.

## Tokenizer Assets

Tokenizer assets are committed under:

- `vendor/tokenizers/<hint>/tokenizer.json`
- `vendor/tokenizers/<hint>/source.json`

Update them via:

```sh
script/download_tokenizers.rb --check
script/download_tokenizers.rb --only deepseek-v3,qwen3 --force
```

## Definition Of Done (P0)

- [ ] Production boot preloads tokenizers with `strict: true`.
- [ ] Estimation hot paths never raise and always return an Integer.
- [ ] `context[:token_estimation]` injection documented and covered by tests.
- [ ] `:prepare` step documents precedence rules and sources (`:context` vs `:default`).
