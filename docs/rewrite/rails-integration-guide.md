# Rails Integration Guide (for the rewrite)

This guide explains how a downstream Rails app should integrate TavernKit for
prompt building, without pulling UI/persistence/network responsibilities into
the gem.

Scope:
- how to call `TavernKit::SillyTavern.build` / `TavernKit::RisuAI.build`
- what data Rails should persist
- what state must stay synchronized between the app and the pipeline
- where file I/O and other side effects belong

## Mental Model

TavernKit is a CPU-bound prompt builder:

```
app state + content  ->  (TavernKit pipeline)  ->  Prompt::Plan  ->  dialect messages
```

The Rails app owns:
- persistence (DB)
- file I/O (uploads, storage, asset import)
- provider networking (OpenAI/Anthropic/etc)
- UI behaviors (including any “interactive directives”)

TavernKit owns:
- parsing/normalizing supported prompt-building formats
- macro expansion + lore activation + injection + trimming/budgeting
- producing a deterministic `Prompt::Plan`

## What Rails Should Persist

### 1) Content models (domain data)

Recommended persisted shapes:
- Character (store CCv2/CCv3 JSON hash, plus an app-level model wrapper)
- Preset / settings (ST preset JSON hash or structured fields)
- Lore books (CC character_book or ST World Info JSON hash)
- Chat history (messages)

TavernKit is hash-first; it can operate directly on `JSON.parse` hashes.

### 2) Session state (must stay in sync)

Two pieces of state are critical:

1) `variables_store` (session-level mutable store)
   - ST: `var` / `globalvar`
   - RisuAI: persisted variables + scriptstate bridges
   - Lifecycle: typically per-chat (persist in DB as JSON, or rebuild from events)

2) `runtime` (per-build app snapshot)
   - chat indices, app metadata, feature toggles, cbs conditions, etc
   - Lifecycle: per prompt build (derive from DB + request context)

Rule of thumb:
- variables_store is *stateful across turns*
- runtime is a *read-only snapshot for this build*

## File I/O and Imports

Core models load from Ruby Hash only:
- `TavernKit::CharacterCard.load(hash)`

On-disk formats are handled by `TavernKit::Ingest`:
- PNG/APNG wrapper
- BYAF / CHARX (ZIP-based; safety limits apply)

Recommended pattern:

```ruby
TavernKit::Ingest.open(upload.path) do |bundle|
  # bundle.character   => TavernKit::Character
  # bundle.main_image_path (optional)
  # bundle.assets      => lazy asset handles (read on demand)
  # bundle.warnings    => import warnings (show to user / log)

  # App decides how to store assets:
  # - attach main_image_path to ActiveStorage
  # - optionally extract other assets lazily via bundle.assets[n].read
end
```

## Building a Prompt (SillyTavern)

```ruby
instrumenter = Rails.env.development? ? TavernKit::Prompt::Instrumenter::TraceCollector.new : nil

plan =
  TavernKit::SillyTavern.build do
    character character_obj
    user user_obj
    history chat_history
    preset st_preset
    lore_books [global_lore, character_lore]

    runtime TavernKit::Runtime::Base.build(
      { chat_index: chat_index, message_index: message_index },
      type: :app,
      id: chat_id,
    )

    variables_store variables_store_obj

    strict Rails.env.test?
    instrumenter instrumenter

    message user_input
  end

payload = plan.to_messages(dialect: :openai, squash_system_messages: st_preset.squash_system_messages)
```

Notes:
- For ST, trimming runs and can attach `plan.trim_report` and `plan.trace` when instrumented.
- Preserve `variables_store` per chat; do not share between concurrent chats.

## Building a Prompt (RisuAI)

```ruby
plan =
  TavernKit::RisuAI.build do
    character character_obj
    user user_obj
    history chat_history
    template_cards risu_prompt_template
    lore_books [risu_lorebook]

    runtime TavernKit::Runtime::Base.build(
      {
        chat_index: chat_index,
        message_index: message_index,
        model: model_name,
        role: "assistant",
        cbs_conditions: {},   # optional
      },
      type: :app,
      id: chat_id,
    )

    variables_store variables_store_obj

    message user_input
  end
```

RisuAI-specific behaviors that depend on app state should be injected through
`runtime` (metadata/toggles/conditions) and adapters (e.g., memory integration).

## Debugging in Rails

Use the debug playbook:
- `plan.debug_dump` (what blocks were produced)
- `plan.trim_report` (budget/evictions; when trimming is used)
- `plan.trace` (when instrumented and attached)
- `plan.fingerprint(...)` (stable repro key)

Recommended env-based switches:
- `strict: true` in tests to fail-fast on warnings
- `instrumenter: TraceCollector.new` in development

