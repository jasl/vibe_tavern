# VibeTavern Prompt Pipeline

`TavernKit::VibeTavern` is the Rails app-owned prompt-building pipeline for the
rewrite. It lives in this app's `lib/` (Zeitwerk autoloaded) and is intended to
evolve independently from the platform pipelines (`SillyTavern` / `RisuAI`).

This document records the currently supported inputs, behaviors, and output
contract so downstream changes can be reviewed against a stable baseline.

## Goals / Non-goals

Goals:
- provide a minimal, deterministic prompt build (history + user input)
- produce a typed `TavernKit::PromptBuilder::Plan` (so the app can render dialect messages)
- keep I/O out of the pipeline (no DB/network/filesystem side effects)
- be easy to extend via additional app-owned steps

Non-goals (for now):
- ST/RisuAI parity behavior (use `TavernKit::SillyTavern` / `TavernKit::RisuAI`)
- lore activation / injection / trimming
- UI behaviors, persistence, or provider networking

## Entry Points

- Build a plan:

```ruby
plan =
  TavernKit::VibeTavern.build do
    history chat_history
    message user_input
  end
```

- Render a plan into dialect messages:

```ruby
messages = plan.to_messages(dialect: :openai)
fingerprint = plan.fingerprint(dialect: :openai)
```

## Minimal PromptRunner + RunnerConfig Example (Copy/Paste)

This is the smallest “end-to-end” example that exercises:

- `RunnerConfig` (typed config + capabilities + configured pipeline)
- `PromptRunner` (single LLM request boundary + preflight)
- step configs via `context[:module_configs]` (e.g. LanguagePolicy)

```ruby
# client must respond to:
# - #chat_completions(**request) -> response with #body (Hash)
client = SimpleInference::Client.new(
  base_url: ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api"),
  api_prefix: ENV.fetch("OPENROUTER_API_PREFIX", "/v1"),
  api_key: ENV.fetch("OPENROUTER_API_KEY"),
)

context = {
  # Protocol/runner configs (strict, symbol keys).
  language_policy: { enabled: true, target_lang: "zh-CN", special_tags: ["lang"] },

  # Per-step overrides (merged on top of step defaults).
  module_configs: {
    language_policy: { style_hint: "casual" },
  },
}

runner_config =
  TavernKit::VibeTavern::RunnerConfig.build(
    provider: "openrouter",
    model: "openai/gpt-4o-mini",
    context: context,
    llm_options_defaults: { temperature: 0.2 },
  )

prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)

prompt_request =
  prompt_runner.build_request(
    runner_config: runner_config,
    history: [],
    system: nil,
    strict: true,
    dialect: :openai,
  )

result = prompt_runner.perform(prompt_request)
assistant_message = result.assistant_message
```

Notes:

- `context` is the single source of truth for per-run settings.
- Use `context[:module_configs]` for per-step overrides. Unknown step keys are ignored.
- Use `RunnerConfig.build(step_options: ...)` only when you want to change step defaults
  outside of the context object (e.g. “system-wide” tuning in scripts).

## Supported Inputs (DSL)

`TavernKit::VibeTavern.build { ... }` uses the PromptBuilder DSL (it is backed by
`TavernKit::PromptBuilder`).

Currently used by this pipeline:
- `history(...)` (required for prior messages; chronological)
- `message(...)` (the current user input; blank after `.strip` is ignored)
- `character(...)` (optional; used for the default `system` block and post-history instructions)
- `user(...)` (optional; used for the default `system` block)
- `context(...)` (optional; see Context Contract)
- `variables_store(...)` (optional; will be defaulted if not provided)
- `token_estimator(...)` (optional; defaults to `TavernKit::TokenEstimator.default`)
- `strict(...)` (optional; affects warning handling across TavernKit)
- `instrumenter(...)` (optional; enables lightweight instrumentation events)
- `meta(:system_template, "...")` (optional; Liquid-rendered; prepends a `system` block)
- `meta(:post_history_template, "...")` (optional; Liquid-rendered; inserts a post-history `system` block)

Accepted by the DSL but currently **ignored** by this pipeline (no behavior yet):
- `dialect(...)`
- `preset(...)`
- `lore_books(...)`, `lore_engine(...)`
- `expander(...)`
- ST/RisuAI-specific metadata fields (these belong in platform pipelines)

## Output Contract

The pipeline produces a `TavernKit::PromptBuilder::Plan` with:
- `blocks`: built from `history` plus an optional `user_message` block
- `warnings`: whatever was collected in the context (usually empty here)
- `trace`: `nil` (today; future steps may attach richer trace objects)

The plan can then be rendered by `plan.to_messages(dialect: ...)`.

## Block Semantics (System + History + Post-history + User Message)

Implementation: `lib/tavern_kit/vibe_tavern/prompt_builder/steps/plan_assembly.rb`

System block (optional):
- If `meta(:system_template, ...)` is present:
  - blank (`nil` / `""` / whitespace-only) disables the system block entirely
  - non-blank is Liquid-rendered using `LiquidMacros.render_for(ctx, ...)` and
    inserted as the first block (`source: :system_template`)
- Else, if `character` or `user` is present:
  - a deterministic "default system" block is built from:
    - `character.data.system_prompt` (if present)
    - `character.display_name` (nickname if present) as `You are {char}.`
    - `character.data.description`, `character.data.personality`
    - `character.data.scenario` (prefixed as `Scenario:`)
    - `user.persona_text` (prefixed as `User persona:`)
  - inserted as the first block (`source: :default_system`)

History:
- Each history message becomes a `TavernKit::PromptBuilder::Block` with:
  - `role`: `message.role`
  - `content`: `message.content.to_s`
  - `name`: `message.name` (if provided)
  - `attachments`: `message.attachments` (if provided)
  - `message_metadata`: `message.metadata` (passed through to dialects that support it)
  - `slot`: `:history`
  - `token_budget_group`: `:history`
  - `metadata`: `{ source: :history }`

Post-history instructions (optional):
- If `meta(:post_history_template, ...)` is present:
  - blank (`nil` / `""` / whitespace-only) disables post-history insertion
  - non-blank is Liquid-rendered and inserted **after history** as a `system` block:
    - `slot`: `:post_history_instructions`
    - `token_budget_group`: `:system`
    - `metadata`: `{ source: :post_history_template }`
- Else, if `character.data.post_history_instructions` is present:
  - inserted **after history** as a plain-text `system` block:
    - `slot`: `:post_history_instructions`
    - `token_budget_group`: `:system`
    - `metadata`: `{ source: :post_history_instructions }`

User input:
- If `ctx.user_message.to_s.strip` is not empty, it becomes one block:
  - `role`: `:user`
  - `content`: the raw user text (not stripped)
  - `slot`: `:user_message`
  - `token_budget_group`: `:history`
  - `metadata`: `{ source: :user_message }`

Notes:
- This pipeline is still intentionally small: it does not do ST/RisuAI parity
  behavior, lore/injection/trimming, or any provider networking.
- Message metadata passthrough matters for OpenAI-style tool call flows:
  when a history message includes `metadata[:tool_calls]` / `:tool_call_id`,
  dialect rendering can include those fields.

Liquid rendering:
- Only `system_template` and `post_history_template` are Liquid-rendered today.
  Raw character card text fields (like `post_history_instructions`) are treated
  as plain text by default for safety and predictability.

## Context Contract

VibeTavern uses context as the "app snapshot" for a build. You can pass:
- a `TavernKit::PromptBuilder::Context` instance (recommended), or
- a Hash (treated as context input and normalized by the pipeline)

Normalization (Prepare step):
- if context is provided as a Hash, the pipeline converts it to a context object:
  `TavernKit::PromptBuilder::Context.build(hash, type: :app)`

Immutability:
- `context` cannot be replaced once the pipeline starts executing steps.
  If you need different context values, construct a new context instance per build.

Key normalization:
- TavernKit normalizes **top-level** context keys (snake_case symbols) when you
  build a context from a Hash.
- Nested hashes inside context (e.g. `context[:toggles]`) are **not** auto-normalized.
  If you rely on toggles (e.g. `:expand_user_input_macros`), normalize those keys
  in the app before injecting context.

## VariablesStore Contract

`variables_store` is session-level mutable state owned by the Rails app.

Defaults:
- if not provided, the pipeline creates `TavernKit::VariablesStore::InMemory.new`

Lifecycle recommendation:
- one store per chat session (persist it in the DB as JSON, or rebuild from events)
- never share a store across concurrent chats
- to avoid interleaving writes, wrap "build plan + persist store" in a chat-level lock

## Instrumentation

If `instrumenter` is present:
- PlanAssembly emits a lightweight stat:
  - `event: :stat`
  - `step: :plan_assembly`
  - `key: :plan_blocks`
  - `value: blocks.size`

Use `TavernKit::PromptBuilder::Instrumenter::TraceCollector` in development if you want
to collect events for debugging.

## Default Steps (Order)

Default pipeline: `lib/tavern_kit/vibe_tavern/pipeline.rb`

Order:

1. `:prepare` (`TavernKit::VibeTavern::PromptBuilder::Steps::Prepare`)
2. `:plan_assembly` (`TavernKit::VibeTavern::PromptBuilder::Steps::PlanAssembly`)
3. `:language_policy` (`TavernKit::VibeTavern::PromptBuilder::Steps::LanguagePolicy`)

## Step Config Reference

This section is the “single table” for how each step is configured and what
it consumes.

### Config Sources (Two Levels)

Step config is merged from:

1. Static defaults (pipeline `use_step` and/or `RunnerConfig.build(step_options: ...)`)
2. Per-run overrides: `context.module_configs[step_name]` (aka `configs:`)

For steps that define a typed config (`StepClass::Config`), keys are validated
by `Config.from_hash` (unknown keys fail fast).

### `:prepare` (`Steps::Prepare`)

Typed step config: `Steps::Prepare::Config` (no fields today).

Behavior config (context-owned, not step options):

- `context[:token_estimation]` (Hash; optional)
  - `model_hint` (String)
  - `token_estimator` (responds to `#estimate`)
  - `registry` (Hash; passed to `TavernKit::TokenEstimator.new(registry: ...)`)
- Meta key: `meta(:default_model_hint, provider_model_id)` (set by `PromptRunner`)

Common pitfall:

- Do not put token estimation settings under `configs[:prepare]`. Those will
  error (the step has no step-level config keys).

### `:plan_assembly` (`Steps::PlanAssembly`)

Typed step config: `Steps::PlanAssembly::Config`

Schema:

- `default_system_text_builder` (callable; optional)
  - default: `nil` (uses the built-in deterministic builder)

Template inputs (metadata):

- `meta(:system_template, ...)` (Liquid; blank disables system block)
- `meta(:post_history_template, ...)` (Liquid; blank disables post-history block)

Common pitfalls:

- Prefer setting callables via `RunnerConfig.build(step_options: ...)` so your
  context stays serializable.
- Builders should be deterministic and return a String (blank disables default system).

### `:language_policy` (`Steps::LanguagePolicy`)

Typed step config: `Steps::LanguagePolicy::Config`

Primary configuration (context-owned, parsed by `RunnerConfig` and injected as step defaults):

- `context[:language_policy]`
  - `enabled` (Boolean; default false)
  - `target_lang` (String; canonicalized)
  - `style_hint` (String; optional)
  - `special_tags` (Array<String>; optional)
  - `policy_text_builder` (callable; optional)

Per-run step overrides (`configs:` / `context.module_configs[:language_policy]`) are deep-merged on top:

- `style_hint` is the most common override (e.g. “casual” vs “formal”)

Common pitfalls:

- If `target_lang` is not in the allowlist, the step warns and does nothing for that run.
- Add `"lang"` to `special_tags` if you want mixed-language spans via `<lang code=\"...\">...</lang>`.

## When to Use Platform Pipelines Instead

If you need parity with:
- SillyTavern: use `TavernKit::SillyTavern.build`
- RisuAI: use `TavernKit::RisuAI.build`

See: `docs/rewrite/rails-integration-guide.md` (Appendices).
