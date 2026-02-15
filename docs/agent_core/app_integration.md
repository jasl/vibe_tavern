# AgentCore app integration (Vibe Tavern)

This app uses `AgentCore` as the execution layer (provider adapter + runner).

For now, we intentionally **do not** port TavernKit prompt pipeline steps (e.g.
`plan_assembly`, `available_skills`, `language_policy`, `output_tags`) into
AgentCore core. App-specific glue lives in `lib/agent_core/contrib` so it can
also be reused from `script/eval` without relying on Rails models.

The primary app-side entrypoint is:

- `AgentCore::Contrib::AgentSession` (wraps `AgentCore::Agent` and integrates
  directives + final-only language policy rewrite).

## `LLM::RunChat`

`LLM::RunChat` normalizes inputs and merges LLM options, then runs via:

- `system` (optional, sent as a system message)
- `history` (OpenAI-ish messages)
- `user_text` (appended as the last user message)
- merged LLM options (provider defaults + preset overrides + per-call overrides)

Execution happens through:

- `AgentCore::Resources::Provider::SimpleInferenceProvider` (OpenAI-compatible)
- `AgentCore::Contrib::AgentSession` (wraps `AgentCore::Agent`)

Notes:

- `AgentSession` supports injecting `tools_registry`, `tool_policy`, and
  `tool_executor` (for confirm/defer pause-resume flows).
- `LLM::RunChat` currently runs with `tools: []` and does not pass tool wiring by
  default (intentional: directives mode forbids tool calls; chat mode can be
  enabled incrementally).

For debugging, `LLM::RunChat` still returns an `AgentCore::PromptBuilder::BuiltPrompt`
representing the effective prompt, but the run itself is executed through
`AgentSession`.

## Token budgeting (preflight)

`LLM::RunChat` keeps the existing `PROMPT_TOO_LONG` behavior by using
`AgentCore::PromptRunner::Runner`'s preflight budget check:

- `context_window` comes from `LLMModel#context_window_tokens` (0 disables checks)
- `reserved_output_tokens` comes from the effective `llm_options[:max_tokens]`
- per-message overhead comes from `LLMModel#effective_message_overhead_tokens`

### Supplying a real estimator

In Rails, if `AgentCore::Contrib::TokenEstimation` is configured (see
`config/initializers/token_estimation.rb`), `LLM::RunChat` will use it by
default when `context[:token_estimation][:token_estimator]` is not provided.

To override, pass a token estimator through `context[:token_estimation]`:

```ruby
context = {
  token_estimation: {
    token_estimator: my_estimator, # must respond to #estimate(text, model_hint:)
    model_hint: "gpt-5.2-chat",
  },
}
```

App-side wrappers:

- `AgentCore::Contrib::TokenCounter::Estimator` wraps `token_estimator#estimate`
- `AgentCore::Contrib::TokenCounter::HeuristicWithOverhead` is the fallback

## Directives (structured envelope)

This app can request a **single JSON object** response shaped like:

- `assistant_text: String`
- `directives: Array<{ type: String, payload: Object }>`

Implementation:

- `AgentCore::Contrib::Directives` (parser/validator + fallback runner)
- `LLM::RunDirectives` (app service, similar to `LLM::RunChat`)

Runner strategy:

- tries `json_schema` → `json_object` → `prompt_only` (configurable)
- each mode can do a small “repair” retry if the model returns invalid JSON

Security / safety boundaries:

- output size guard: `AgentCore::Contrib::Directives::Parser::DEFAULT_MAX_BYTES` (200KB)
- patch ops helper: `AgentCore::Contrib::Directives::Validator.normalize_patch_ops`
  - only allows `op: set|delete|append|insert` (with common aliases)
  - only allows paths under `/draft/` or `/ui_state/` by default

Important: **Directives mode forbids tool calls.** If the assistant emits tool calls, it is treated as an invalid response and will not be executed.

## Language policy: final-only rewrite

Injecting “respond in X language” constraints into the main tool-calling loop can reduce tool-calling reliability. Recommended approach:

1) run the tool loop without language constraints
2) when you have the final assistant text, rewrite it into the target language with a second request **without tools**

Helper:

- `AgentCore::Contrib::LanguagePolicy::FinalRewriter`

Notes:

- When the target language is a CJK language (`zh-*`/`ja-JP`/`ko-KR`/`yue-HK`),
  the rewriter uses a conservative script-based detector and **skips the rewrite
  call** when the text already looks like the target language.
- When language policy is enabled and the caller requests streaming, the app
  buffers the run and emits **final-only** events (the rewritten final text).

Example (pure Ruby; no Rails model dependency):

```ruby
rewritten =
  AgentCore::Contrib::LanguagePolicy::FinalRewriter.rewrite(
    provider: provider,
    model: "m1",
    text: final_text,
    target_lang: "zh-CN",
    llm_options: { max_tokens: 2000, temperature: 0 },
  )
```

Guardrail:

- if `text` is larger than 200KB, the rewriter returns the input unchanged (to avoid accidental truncation).

## Pause/resume entrypoint (recommended)

For app/UI code, prefer pausing and resuming via `AgentCore::Contrib::AgentSession`
instead of calling `PromptRunner::Runner#resume*` directly:

- confirmation pause: `#resume` / `#resume_stream`
- deferred execution pause: `#resume_with_tool_results` / `#resume_stream_with_tool_results`

This keeps the app-level session history consistent and centralizes policy glue.

## Persisting continuations (production)

If you need to pause and resume across processes (web ↔ jobs, deploys, etc.),
persist `RunResult#continuation` using a JSON-safe, versioned payload:

- `AgentCore::PromptRunner::ContinuationCodec.dump(continuation, context_keys: [...])`
- `AgentCore::PromptRunner::ContinuationCodec.load(payload)`

Guidelines:

- Only persist explicitly allowlisted `context_keys` (tenant/user/workspace ids).
- Never persist secrets (tokens/headers/env).
- Prefer passing a **fresh** context on resume (current tenant/user/workspace),
  and treat stored `context_attributes` as an optional hint.
