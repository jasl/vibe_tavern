# VibeTavern Prompt Pipeline

`TavernKit::VibeTavern` is the Rails app-owned prompt-building pipeline for the
rewrite. It lives in this app's `lib/` (Zeitwerk autoloaded) and is intended to
evolve independently from the platform pipelines (`SillyTavern` / `RisuAI`).

This document records the currently supported inputs, behaviors, and output
contract so downstream changes can be reviewed against a stable baseline.

## Goals / Non-goals

Goals:
- provide a minimal, deterministic prompt build (history + user input)
- produce a typed `TavernKit::Prompt::Plan` (so the app can render dialect messages)
- keep I/O out of the pipeline (no DB/network/filesystem side effects)
- be easy to extend via additional app-owned middlewares

Non-goals (for now):
- ST/RisuAI parity behavior (use `TavernKit::SillyTavern` / `TavernKit::RisuAI`)
- macro expansion / lore activation / injection / trimming
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

## Supported Inputs (DSL)

`TavernKit::VibeTavern` uses the standard TavernKit DSL (`TavernKit.build { ... }`).

Currently used by this pipeline:
- `history(...)` (required for prior messages; chronological)
- `message(...)` (the current user input; blank after `.strip` is ignored)
- `runtime(...)` (optional; see Runtime Contract)
- `variables_store(...)` (optional; will be defaulted if not provided)
- `token_estimator(...)` (optional; defaults to `TavernKit::TokenEstimator.default`)
- `strict(...)` (optional; affects warning handling across TavernKit)
- `instrumenter(...)` (optional; enables lightweight instrumentation events)

Accepted by the DSL but currently **ignored** by this pipeline (no behavior yet):
- `dialect(...)`
- `character(...)`, `user(...)`
- `preset(...)`
- `lore_books(...)`, `lore_engine(...)`
- `expander(...)`
- ST/RisuAI-specific metadata fields (these belong in platform pipelines)

## Output Contract

The pipeline produces a `TavernKit::Prompt::Plan` with:
- `blocks`: built from `history` plus an optional `user_message` block
- `warnings`: whatever was collected in the context (usually empty here)
- `trace`: `nil` (today; future middlewares may attach richer trace objects)

The plan can then be rendered by `plan.to_messages(dialect: ...)`.

## Block Semantics (History + User Message)

Implementation: `lib/tavern_kit/vibe_tavern/middleware/plan_assembly.rb`

History:
- Each history message becomes a `TavernKit::Prompt::Block` with:
  - `role`: `message.role`
  - `content`: `message.content.to_s`
  - `name`: `message.name` (if provided)
  - `attachments`: `message.attachments` (if provided)
  - `message_metadata`: `message.metadata` (passed through to dialects that support it)
  - `slot`: `:history`
  - `token_budget_group`: `:history`
  - `metadata`: `{ source: :history }`

User input:
- If `ctx.user_message.to_s.strip` is not empty, it becomes one block:
  - `role`: `:user`
  - `content`: the raw user text (not stripped)
  - `slot`: `:user_message`
  - `token_budget_group`: `:history`
  - `metadata`: `{ source: :user_message }`

Notes:
- This pipeline does **not** insert system messages, character cards, lore, or
  any special injections yet.
- Message metadata passthrough matters for OpenAI-style tool call flows:
  when a history message includes `metadata[:tool_calls]` / `:tool_call_id`,
  dialect rendering can include those fields.

## Runtime Contract

VibeTavern uses runtime as the "app snapshot" for a build. You can pass:
- a `TavernKit::Runtime::Base` instance (recommended), or
- a Hash (treated as runtime input and normalized by the pipeline)

Normalization (Prepare middleware):
- if runtime is provided as a Hash, the pipeline converts it to a runtime object:
  `TavernKit::Runtime::Base.build(hash, type: :app)`

Immutability:
- `runtime` cannot be replaced once the pipeline starts executing middlewares.
  If you need different runtime values, construct a new runtime instance per build.

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
  - `stage: :plan_assembly`
  - `key: :plan_blocks`
  - `value: blocks.size`

Use `TavernKit::Prompt::Instrumenter::TraceCollector` in development if you want
to collect events for debugging.

## When to Use Platform Pipelines Instead

If you need parity with:
- SillyTavern: use `TavernKit::SillyTavern.build`
- RisuAI: use `TavernKit::RisuAI.build`

See: `docs/rewrite/rails-integration-guide.md` (Appendices).

