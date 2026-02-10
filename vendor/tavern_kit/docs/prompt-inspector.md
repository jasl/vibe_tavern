# PromptInspector (Debug)

`TavernKit::PromptInspector` is a **debug-only** utility for inspecting prompt
plans/messages and understanding how token budgets are being consumed.

It is intentionally separate from the hot-path trimming/budgeting logic:

- Hot path: use `TokenEstimator#estimate` (fast, no allocations beyond ids)
- Debug path: use `PromptInspector` (allocates tokenization detail when available)

## What it does

Given a `TavernKit::Prompt::Plan` or a message array, it returns:

- totals (content + metadata + overhead)
- per-message breakdown
- optional tokenization detail (backend dependent)

This is useful for:

- verifying trimming/budget settings (`message_overhead_tokens`, metadata counting)
- comparing estimates across model families
- debugging “why did we overflow?” cases

## Usage

Inspect a plan:

```ruby
inspection =
  TavernKit::PromptInspector.inspect_plan(
    plan,
    token_estimator: ctx.token_estimator,
    model_hint: ctx[:model_hint],
    message_overhead_tokens: preset.message_token_overhead,
    include_message_metadata_tokens: false,
  )

inspection.totals.total_tokens
inspection.messages.first.total_tokens
inspection.estimator # backend + registry metadata (if matched)
```

Inspect messages directly (supports `TavernKit::Prompt::Message` and `Hash`):

```ruby
inspection =
  TavernKit::PromptInspector.inspect_messages(
    messages,
    token_estimator: TavernKit::TokenEstimator.default,
    model_hint: "qwen3",
    message_overhead_tokens: 0,
    include_message_metadata_tokens: true,
    include_metadata_details: true,
  )
```

### Metadata counting

When `include_message_metadata_tokens: true`, metadata is counted by serializing
the metadata hash via `JSON.generate`. If JSON serialization fails (encoding or
type issues), it falls back to `meta.to_s`.

This matches the `MaxTokensMiddleware` strategy and keeps the behavior
deterministic.

## Tokenization detail by backend

`PromptInspector` uses `TokenEstimator#tokenize` when available.

- `tiktoken` backend:
  - returns `ids` only (`tokens`/`offsets` are `nil`)
  - reason: `tiktoken_ruby` cannot reliably decode a *single* token id into
    valid UTF-8 (multi-byte sequences like emoji can span multiple tokens)
- `hf_tokenizers` backend (`tokenizers` gem + local `tokenizer.json`):
  - returns `ids` + `tokens` + `offsets`
  - offsets are **character offsets** (Ruby string indices), not byte offsets

When a registry entry is used, inspector output includes registry metadata:

- top-level: `inspection.estimator[:registry_source_hint]`,
  `inspection.estimator[:registry_source_repo]`, `inspection.estimator[:registry_tokenizer_family]`
- per-message tokenization: `inspection.messages[i].content_tokenization.details`
  includes the same registry fields

## Performance notes

- `inspect_*` allocates per-message inspection objects and (depending on
  backend) token arrays. Avoid calling it in request hot paths.
- For high-frequency checks (trimming, budget enforcement), use `estimate`.

## Accuracy notes

Even with the correct tokenizer, provider-side “chat template” wrapping can add
tokens that the client cannot perfectly reproduce. Use:

- `message_overhead_tokens` (per message) and conservative headroom
- provider `usage` (when available) to calibrate heuristics and margins
