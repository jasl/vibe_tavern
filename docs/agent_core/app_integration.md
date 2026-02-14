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
