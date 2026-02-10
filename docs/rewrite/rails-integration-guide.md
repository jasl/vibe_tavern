# Rails Integration Guide (for the rewrite)

This guide explains how a downstream Rails app should integrate TavernKit for
prompt building, without pulling UI/persistence/network responsibilities into
the gem.

Scope:
- how to call `TavernKit::VibeTavern.build` (app-owned pipeline for the rewrite)
- how to call `TavernKit::SillyTavern.build` / `TavernKit::RisuAI.build` (compat/parity modes)
- how to define and call additional app-owned pipelines (including custom macro systems)
- what data Rails should persist
- what state must stay synchronized between the app and the pipeline
- where file I/O and other side effects belong

## Mental Model

TavernKit is a CPU-bound prompt builder:

```
app state + content  ->  (TavernKit pipeline)  ->  PromptBuilder::Plan  ->  dialect messages
```

The Rails app owns:
- persistence (DB)
- file I/O (uploads, storage, asset import)
- provider networking (OpenAI/Anthropic/etc)
- UI behaviors (including any “interactive directives”)

TavernKit owns:
- parsing/normalizing supported prompt-building formats
- macro expansion + lore activation + injection + trimming/budgeting
- producing a deterministic `PromptBuilder::Plan`

## What Rails Should Persist

### 1) Content models (domain data)

Recommended persisted shapes:
- Character (store CCv2/CCv3 JSON hash, plus an app-level model wrapper)
- Preset / settings (ST preset JSON hash or structured fields)
- RisuAI prompt template (stored in the RisuAI preset under `promptTemplate`; optionally persisted separately and merged at build-time)
- Lore books (CC character_book or ST World Info JSON hash)
- Chat history (messages)

TavernKit is hash-first at boundaries; it can operate directly on `JSON.parse` hashes.
Some pipelines expect typed objects (created via hash-only importers):
- ST preset: `TavernKit::SillyTavern::Preset::StImporter.new(hash).to_preset`
- ST World Info: `TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(hash)`

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

## Chat History (Message Contract)

`history` can be `nil`, an `Array`, an `Enumerable`, or a `TavernKit::ChatHistory::Base`.
Each message is recommended to be a `TavernKit::PromptBuilder::Message`, but can also be a Hash
or a duck-typed object that responds to `role` and `content`.

Ordering matters: `history` must be chronological (oldest -> newest).

Example (ActiveRecord relation):

```ruby
history = chat.messages.order(:id) # must yield oldest -> newest
```

## File I/O and Imports

Core models load from Ruby Hash only:
- `TavernKit::CharacterCard.load(hash)`

On-disk formats are handled by `TavernKit::Ingest`:
- PNG/APNG wrapper
- BYAF / CHARX (ZIP-based; safety limits apply)

Note for Rails:
- For ActiveStorage blobs, prefer `blob.open { |file| TavernKit::Ingest.open(file.path) { ... } }`
  so you always get a real filesystem path and an explicit tmp lifetime.

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

## Default Prompt Build (VibeTavern)

```ruby
instrumenter = Rails.env.development? ? TavernKit::PromptBuilder::Instrumenter::TraceCollector.new : nil

plan =
  TavernKit::VibeTavern.build do
    history chat_history

    character character_obj
    user user_obj

    runtime TavernKit::PromptBuilder::Context.build(
      { chat_index: chat_index, message_index: message_index },
      type: :app,
      id: chat_id,
    )

    variables_store variables_store_obj

    strict Rails.env.test?
    instrumenter instrumenter

    # Optional: VibeTavern-only system template (Liquid-rendered).
    # Prefer this over expanding user input at build time.
    meta :system_template, system_template_text

    # Optional: VibeTavern-only post-history template (Liquid-rendered).
    # If omitted, VibeTavern inserts `character.data.post_history_instructions`
    # after history (plain text) when present.
    meta :post_history_template, post_history_template_text

    message user_input
  end

payload = plan.to_messages(dialect: :openai)
fingerprint = plan.fingerprint(dialect: :openai)
```

Notes:
- `TavernKit::VibeTavern` is intentionally minimal, but it does insert a
  deterministic default system block when `character`/`user` are provided, and
  it inserts `post_history_instructions` after history when present on the card.
- To disable those default insertions explicitly:
  - `meta :system_template, nil` disables the system block
  - `meta :post_history_template, nil` disables post-history insertion
- Preserve `variables_store` per chat; do not share it between concurrent chats.
- See `docs/rewrite/vibe-tavern-pipeline.md` for the precise supported contract and behaviors.
- For the Liquid-based macros system (variables + side-effect tags), see `docs/research/vibe_tavern/macros.md`.
- If you want “user input also runs macros/scripts” (ST/RisuAI-style), keep it
  app-owned and run it **before persistence** using:
  `TavernKit::VibeTavern::UserInputPreprocessor.call(...)`.
  Default toggle: `runtime[:toggles][:expand_user_input_macros]` (off by default).
  Important: `runtime[:toggles]` must use **snake_case symbol keys**.
  If you load toggles from JSON (string keys), normalize before building runtime:

  ```ruby
  toggles = json_toggles.to_h.transform_keys { |k| TavernKit::Utils.underscore(k).to_sym }
  runtime = TavernKit::PromptBuilder::Context.build({ toggles: toggles }, type: :app, id: chat.id)
  ```

## Extending / Adding App-owned Pipelines

If the rewrite wants additional pipelines beyond `TavernKit::VibeTavern`, keep
them app-owned and call TavernKit with an explicit `pipeline:`:

```ruby
# lib/prompt_building/pipeline.rb (app-owned)
module PromptBuilding
  Pipeline = TavernKit::PromptBuilder::Pipeline.new do
    # Compose your own step chain here (and your own macro system if desired).
    #
    # Example:
    # use MyApp::PromptBuilding::PromptBuilder::Steps::Prepare, name: :prepare
  end
end
```

```ruby
plan =
  TavernKit.build(pipeline: PromptBuilding::Pipeline) do
    # Same DSL inputs (character/user/history/preset/lore_books/runtime/etc)
    message user_input
  end
```

## Persistence + Concurrency (VariablesStore)

`variables_store` is session-level mutable state. Pipelines may mutate it
through macros/triggers. Rails should persist it back to the chat record
**after** building a plan.

Note:
- `TavernKit::VariablesStore::InMemory` is a convenient default for tests.
- In a Rails app, prefer injecting an application-owned variables store that is
  both a `VariablesStore` and serializable (so you can persist it back to JSONB
  after the build).

Recommended default (simple and safe):
- Wrap “build plan + persist variables_store” in `chat.with_lock` (or a DB
  transaction with row locking) so concurrent builds for the same chat cannot
  interleave and corrupt store state.

## Debugging in Rails

Use the debug playbook:
- `plan.debug_dump` (what blocks were produced)
- `plan.trim_report` (budget/evictions; when trimming is used)
- `plan.trace` (when instrumented and attached)
- `plan.fingerprint(...)` (stable repro key)

Recommended env-based switches:
- `strict: true` in tests to fail-fast on warnings
- `instrumenter: TraceCollector.new` in development

---

## Appendix: SillyTavern Pipeline (parity mode)

Use this when you explicitly want ST behavior parity.

```ruby
instrumenter = Rails.env.development? ? TavernKit::PromptBuilder::Instrumenter::TraceCollector.new : nil

plan =
  TavernKit::SillyTavern.build do
    dialect :openai
    character character_obj
    user user_obj
    history chat_history
    preset st_preset
    lore_books [global_lore, character_lore]

    runtime TavernKit::PromptBuilder::Context.build(
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
- ST pipeline validates required inputs (`character` and `user`) at build time.
- For ST, trimming runs and can attach `plan.trim_report` and `plan.trace` when instrumented.
- For continue/impersonate/quiet behavior parity, set `generation_type` explicitly
  (`:continue`, `:impersonate`, `:quiet`, etc).

## Appendix: RisuAI Pipeline (parity mode)

Use this when you explicitly want RisuAI behavior parity (prompt-building subset).

```ruby
plan =
  TavernKit::RisuAI.build do
    dialect :openai
    character character_obj
    user user_obj
    history chat_history
    preset risu_preset_hash # contains `promptTemplate` (or `prompt_template`)
    lore_books [risu_lorebook]

    runtime TavernKit::PromptBuilder::Context.build(
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

    strict Rails.env.test?

    message user_input
  end
```

RisuAI-specific behaviors that depend on app state should be injected through
`runtime` (metadata/toggles/conditions) and adapters (e.g., memory integration).
