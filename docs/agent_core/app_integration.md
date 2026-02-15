# AgentCore app integration (Vibe Tavern)

This app uses `AgentCore` as the execution layer (provider adapter + runner).

For now, we intentionally **do not** port TavernKit prompt pipeline steps (e.g.
`plan_assembly`, `available_skills`, `language_policy`, `output_tags`) into
AgentCore core. App-specific glue lives in `lib/agent_core/contrib` so it can
also be reused from `script/eval` without relying on Rails models.

## `LLM::RunChat`

`LLM::RunChat` builds an `AgentCore::PromptBuilder::BuiltPrompt` from:

- `system` (optional, sent as a system message)
- `history` (OpenAI-ish messages)
- `user_text` (appended as the last user message)
- merged LLM options (provider defaults + preset overrides + per-call overrides)

It then runs the prompt via:

- `AgentCore::Resources::Provider::SimpleInferenceProvider` (OpenAI-compatible)
- `AgentCore::PromptRunner::Runner` (tool loop engine; tools are not wired in yet)

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
