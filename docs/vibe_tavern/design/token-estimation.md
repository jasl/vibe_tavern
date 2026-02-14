# Token Estimation (VibeTavern)

Token estimation is used for:

- prompt budgeting / trimming (avoid context-length errors)
- observability (budget stats in traces)
- debug inspection (why did we overflow?)

This repo keeps the token estimator implementation in app-side
`AgentCore::Contrib` (`lib/agent_core/contrib/`) and keeps provider/model
mapping in `AgentCore::Contrib::TokenEstimation`.

## Core building blocks (AgentCore::Contrib)

Core API: `AgentCore::Contrib::TokenEstimator`

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
- `lib/agent_core/contrib/token_estimator.rb`
- legacy design notes: `vendor/tavern_kit/docs/core-interface-design.md`
- legacy inspector notes: `vendor/tavern_kit/docs/prompt-inspector.md`

### HF tokenizer.json backend

For common OSS model families (DeepSeek/Qwen/Llama/etc.), Core supports:

- `tokenizer_family: :hf_tokenizers`
- `tokenizer_path: "/abs/path/to/tokenizer.json"`

This uses the `tokenizers` gem (Rust HF tokenizers bindings) to load a local
`tokenizer.json`. There are **no on-demand downloads** in Core.

## VibeTavern default integration (Rails app)

VibeTavern provides an app-owned registry + canonicalization layer:

- `AgentCore::Contrib::TokenEstimation.canonical_model_hint(model_id)`
  - maps provider model ids/variants into a small canonical set
  - example: `deepseek/deepseek-chat-v3-0324:nitro` → `deepseek-v3`
- `AgentCore::Contrib::TokenEstimation.registry`
  - maps canonical hints to backend entries (HF tokenizer.json or `tiktoken`)
  - carries source metadata (`source_hint`, `source_repo`) for inspector/debug
- `AgentCore::Contrib::TokenEstimation.estimator`
  - memoized `AgentCore::Contrib::TokenEstimator` configured with the registry

`LLM::RunChat` (AgentCore runner integration) applies these defaults:

- when `context[:token_estimation][:model_hint]` is blank/missing, it uses the
  request model id (`llm_model.model`) and canonicalizes it.
- when `context[:token_estimation][:token_estimator]` is not explicitly set, it
  defaults to `TokenEstimation.estimator`.

### Injection points (Context + Step behavior)

Primary injection point for `LLM::RunChat`:

- `context[:token_estimation]` (Hash; programmer-owned)

```ruby
context = {
  token_estimation: {
    # Optional: overrides model hint selection.
    model_hint: "deepseek/deepseek-chat-v3-0324:nitro",

    # Optional: override the estimator directly.
    # token_estimator: my_estimator, # responds to #estimate

    # Optional: override the registry (Core will build an estimator from it).
    # registry: { "deepseek-v3" => { tokenizer_family: :hf_tokenizers, tokenizer_path: "/abs/..." } },
  },
}
```

Model hint selection precedence:

1) `context[:token_estimation][:model_hint]` when present and non-blank
2) request model id (`llm_model.model`)

Estimator selection precedence:

1) `context[:token_estimation][:token_estimator]`
2) `context[:token_estimation][:registry]` (build `AgentCore::Contrib::TokenEstimator.new(registry: ...)`)
3) default `AgentCore::Contrib::TokenEstimation.estimator`

### Caching strategy

There are two layers of caching:

- App-level estimator instance cache:
  - `AgentCore::Contrib::TokenEstimation.estimator` memoizes a configured
    `AgentCore::Contrib::TokenEstimator` per tokenizer root path.
- Core adapter caches:
  - `TokenEstimator` caches HF tokenizers in an LRU cache (by `tokenizer_path`).
  - `tiktoken` adapter caches encoding selection per `model_hint`.

### Boot-time preload

`config/initializers/token_estimation.rb` runs:

- `TokenEstimation.configure(root: Rails.root, tokenizer_root: Rails.app.creds.option(:token_estimation, :tokenizer_root))`
- `TokenEstimation.estimator.preload!(strict: Rails.env.production?)`
 
(`TokenEstimation` is `AgentCore::Contrib::TokenEstimation`.)

In production, this fails fast if a tokenizer asset is missing/invalid.

### Configuration

Rails:

- `root` is set to `Rails.root` by the initializer.
- `tokenizer_root` is read from credentials (`Rails.app.creds.option(:token_estimation, :tokenizer_root)`).
  - If blank/missing, it falls back to `ENV["TOKEN_ESTIMATION__TOKENIZER_ROOT"]`.

Non-Rails:

- You must provide a root via `AgentCore::Contrib::TokenEstimation.configure(root: ...)` or `ENV["VIBE_TAVERN_ROOT"]`.
- Optional: provide `tokenizer_root` via `AgentCore::Contrib::TokenEstimation.configure(tokenizer_root: ...)` or `ENV["TOKEN_ESTIMATION__TOKENIZER_ROOT"]`.
- If `tokenizer_root` is relative, it is resolved against the configured root.
- There is no `__dir__` fallback; missing root raises at use time.

## Failure / degradation policy

Token estimation is a budgeting/observability helper, not a protocol boundary.

- Hot path: `TokenEstimator#estimate` is defensive and should never raise:
  - configured backend → `tiktoken` → heuristic
  - always returns an Integer
- Deploy-time: `preload!(strict: true)` may raise to catch missing/invalid assets.

## Tokenizer assets (download + commit)

Tokenizer assets live in-repo (not under `/resources`, which is gitignored):

- `vendor/tokenizers/<hint>/tokenizer.json`
- `vendor/tokenizers/<hint>/source.json` (source metadata)

Default tokenizer root is `<root>/vendor/tokenizers` (Rails: `Rails.root/vendor/tokenizers`).
You can override it via credentials:

```yaml
token_estimation:
  tokenizer_root: /absolute/path/to/tokenizers
```

If `tokenizer_root` is relative, it is resolved against `<root>`. If credentials
are blank/missing, `ENV["TOKEN_ESTIMATION__TOKENIZER_ROOT"]` is used as a fallback.

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
script/eval/llm_token_estimator_registry_audit.rb --strict
```

This audits model ids from `script/eval/support/openrouter_models.rb` and reports:

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
