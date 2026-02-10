# TavernKit

TavernKit is a Ruby prompt-building toolkit for LLM chat applications.

It focuses on turning app-owned inputs (character/user/history/preset/lore/context)
into a provider-ready prompt plan and message payloads, with platform layers for:

- **SillyTavern** (`TavernKit::SillyTavern`)
- **RisuAI** (`TavernKit::RisuAI`)

## Scope

In scope:
- step-based prompt pipeline
- macro expansion
- lorebook scanning + injection
- trimming / budgeting
- provider dialect conversion (`:openai`, `:anthropic`, `:text`, ...)
- safe-ish ingestion of common card containers (PNG/APNG, CHARX, BYAF)

Out of scope (application-owned):
- UI rendering
- persistence / database
- network I/O to LLM providers
- vector DB / embeddings (memory retrieval algorithms)
- plugin / Lua systems

## Compatibility + References

This rewrite tracks real-world behavior via characterization tests and
compatibility docs:

- Docs index: `docs/README.md`
- Reference source pins: `docs/reference-sources.md`
- ST compatibility matrix: `docs/compatibility/sillytavern.md`
- RisuAI compatibility matrix: `docs/compatibility/risuai.md`
- Core interfaces: `docs/core-interface-design.md`
- Debugging/observability: `docs/pipeline-observability.md`
- Rails integration notes (host app in this repo): `../../docs/rewrite/rails-integration-guide.md`

## Installation (this repo)

This repository vendors TavernKit as an embedded gem.

```ruby
# Gemfile
gem "tavern_kit", path: "vendor/tavern_kit"
```

## Quickstart

### SillyTavern-style prompt building

```ruby
require "json"
require "tavern_kit"

card_hash = JSON.parse(File.read("my_character.json"))
character = TavernKit::CharacterCard.load_hash(card_hash)

preset_hash = JSON.parse(File.read("my_st_preset.json"))
preset = TavernKit::SillyTavern::Preset::StImporter.new(preset_hash).to_preset

world_info_hash = JSON.parse(File.read("my_world_info.json"))
world_info = TavernKit::SillyTavern::Lore::WorldInfoImporter.load_hash(world_info_hash)

history = TavernKit::ChatHistory::InMemory.new(
  [
    TavernKit::PromptBuilder::Message.new(role: :user, content: "Hi!"),
    TavernKit::PromptBuilder::Message.new(role: :assistant, content: "Hello!"),
  ],
)

plan =
  TavernKit::SillyTavern.build do
    character character
    user TavernKit::User.new(name: "You")
    preset preset
    history history
    lore_book world_info
    message "Continue."
  end

payload = plan.to_messages(dialect: :openai)
fingerprint = plan.fingerprint(dialect: :openai)
```

### RisuAI-style prompt building

RisuAI pipelines are driven by a RisuAI preset hash (including `promptTemplate`)
and app-owned context state (`state.context`) for parity-sensitive fields.

```ruby
require "json"
require "tavern_kit"

risu_preset = JSON.parse(File.read("my_risu_preset.json"))

context_input = {
  chat_index: 123,
  message_index: 50,
  rng_word: "stable-seed",
  run_var: true,
  rm_var: false,
}

plan =
  TavernKit::RisuAI.build do
    preset risu_preset
    character character
    user TavernKit::User.new(name: "You")
    history history
    context context_input
    message "Hello."
  end

payload = plan.to_messages(dialect: :openai)
```

Notes:
- Context input accepts string/camelCase keys; it is normalized once at pipeline
  entry. Internal code relies on canonical snake_case symbol keys.
- `PromptBuilder.new(..., configs: {...})` can provide per-step config
  overrides via `context.module_configs` while keeping context as the single
  external input source.
- `variables_store` is session-level state; persist it per chat (do not share
  across concurrent chats).

PromptBuilder input contract:
- Fixed keyword inputs are strict (`character`, `user`, `history`, `message`,
  `preset`, `dialect`, `strict`, `llm_options`, etc.).
- Unknown input keys fail fast (`ArgumentError`).
- Step config parsing is step-owned and typed (`Step::Config.from_hash`).

## File ingestion (PNG / CHARX / BYAF)

Core objects are hash-first. Use `TavernKit::Ingest` for common on-disk formats:

```ruby
require "tavern_kit"

TavernKit::Ingest.open("my_card.charx") do |bundle|
  character = bundle.character
  main_image_path = bundle.main_image_path

  # Lazy assets (not extracted to disk by default):
  bundle.assets.each do |asset|
    bytes = asset.read(max_bytes: 1_000_000)
  end

  warnings = bundle.warnings
end
```

ZIP-based formats are read through `TavernKit::Archive::ZipReader` which enforces
limits (entry count/size/total budget/path traversal/compression ratio).

## Context + VariablesStore (app/pipeline synchronization)

Two pieces of state commonly need to stay in sync between your app and the
pipeline:

- `state.context`: application-owned, per-build snapshot (chat indices, toggles,
  metadata). Set once at pipeline entry; must not be replaced mid-pipeline.
- `state.variables_store`: application-owned, session-level store (ST `var` +
  `globalvar`, plus RisuAI extensions). Persist it across turns within a chat.

See `docs/core-interface-design.md` for the full contract and
`docs/rewrite/rails-integration-guide.md` for recommended persistence patterns.

## Debugging / Strict mode

- `strict true` is intended for tests/debugging (fail-fast on warnings).
- `instrumenter TavernKit::PromptBuilder::Instrumenter::TraceCollector.new` enables
  detailed step traces and is meant for development only.

See `docs/pipeline-observability.md`.

## Development (embedded gem)

```sh
cd vendor/tavern_kit && bin/setup
cd vendor/tavern_kit && bundle exec rake test
```

## License

MIT. See `LICENSE.txt`.
