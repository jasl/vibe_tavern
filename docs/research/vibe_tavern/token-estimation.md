# Token Estimation (VibeTavern)

Token estimation is used for:

- prompt budgeting / trimming (avoid context-length errors)
- observability (budget stats in traces)
- debug inspection (why did we overflow?)

This repo keeps the **Core** token counting logic in the embedded `tavern_kit`
gem (`vendor/tavern_kit/`) and keeps **provider/model mapping** in the Rails
app (`lib/tavern_kit/vibe_tavern/`).

## Core building blocks (TavernKit)

Core API: `TavernKit::TokenEstimator`

- hot path: `estimate(text, model_hint:) -> Integer`
  - deterministic, fast, and **never raises** on external input
  - fallback chain: configured backend → `tiktoken` → heuristic
- ops: `preload!(strict:) -> { loaded:, failed: }`
  - preloads tokenizer assets so request hot paths don't pay the load cost
  - `strict: true` raises if any configured tokenizer fails to load (deploy-time validation)
- debug: `tokenize(text, model_hint:) -> Tokenization`
  - `tiktoken`: ids only
  - `hf_tokenizers`: ids + tokens + offsets

See:
- `vendor/tavern_kit/docs/core-interface-design.md`
- `vendor/tavern_kit/docs/prompt-inspector.md`

### HF tokenizer.json backend

For common OSS model families (DeepSeek/Qwen/Llama/etc.), Core supports:

- `tokenizer_family: :hf_tokenizers`
- `tokenizer_path: "/abs/path/to/tokenizer.json"`

This uses the `tokenizers` gem (Rust HF tokenizers bindings) to load a local
`tokenizer.json`. There are **no runtime downloads** in Core.

## VibeTavern default integration (Rails app)

VibeTavern provides an app-owned registry + canonicalization layer:

- `TavernKit::VibeTavern::TokenEstimation.canonical_model_hint(model_id)`
  - maps provider model ids/variants into a small canonical set
  - example: `deepseek/deepseek-chat-v3-0324:nitro` → `deepseek-v3`
- `TavernKit::VibeTavern::TokenEstimation.registry`
  - maps canonical hints to backend entries (HF tokenizer.json or `tiktoken`)
  - carries source metadata (`source_hint`, `source_repo`) for inspector/debug
- `TavernKit::VibeTavern::TokenEstimation.estimator`
  - memoized `TavernKit::TokenEstimator` configured with the registry

The VibeTavern pipeline injects these defaults in `Middleware::Prepare`:

- when `ctx[:model_hint]` is not explicitly set, it is derived from
  `ctx[:default_model_hint]` (often the provider model id used for the request)
  and canonicalized.
- when `ctx.token_estimator` is not explicitly set, it defaults to
  `TokenEstimation.estimator`.

### Boot-time preload

`config/initializers/token_estimation.rb` runs:

- `TokenEstimation.estimator.preload!(strict: Rails.env.production?)`

In production, this fails fast if a tokenizer asset is missing/invalid.

## Tokenizer assets (download + commit)

Tokenizer assets live in-repo (not under `/resources`, which is gitignored):

- `vendor/tokenizers/<hint>/tokenizer.json`
- `vendor/tokenizers/<hint>/source.json` (source metadata)

Default root path is `Rails.root/vendor/tokenizers`. You can override it via
credentials:

```yaml
token_estimation:
  tokenizer_root: /absolute/path/to/tokenizers
```

If `tokenizer_root` is relative, it is resolved against `Rails.root`.

Download/update them with:

```sh
script/download_tokenizers.rb
```

Options:

- `--only deepseek-v3,qwen3,kimi-k2.5`
- `--force`
- `--check`

Notes:

- entries with `tokenizer_family: :tiktoken` are skipped by the downloader
  because they do not need local `tokenizer.json`.
- `PromptInspector` can show the selected source via
  `inspection.estimator[:registry_source_hint]` and
  `inspection.estimator[:registry_source_repo]`.

Audit mapping against current eval model set:

```sh
script/llm_token_estimator_registry_audit.rb --strict
```

This scans model declarations from eval scripts and reports:

- model id -> canonical hint
- backend family + source metadata
- tokenizer file presence (for `hf_tokenizers`)

## Accuracy notes

Even with the correct tokenizer, providers may apply a server-side “chat
template” that adds tokens the client cannot perfectly reproduce. Use:

- conservative headroom in max-token settings
- per-message overhead knobs where applicable (`message_overhead_tokens`)
- provider `usage` (when available) to calibrate margins

## Future work

- Claude tokenizer: must be obtained via provider APIs (non-local asset).
- SentencePiece: evaluate a stable Ruby library + bundling story before adding.
- Licensing/attribution for bundled tokenizer assets.
