# TavernKit

TavernKit is a Ruby prompt-building toolkit for LLM chat applications.

It focuses on turning app-owned inputs (character/user/history/preset/lore/runtime)
into a provider-ready prompt plan and message payloads, with platform layers for:

- **SillyTavern** (`TavernKit::SillyTavern`)
- **RisuAI** (`TavernKit::RisuAI`)

## Scope

In scope:
- prompt pipeline / middleware stages
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

- Roadmap / wave plan: `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md`
- ST compatibility matrix: `docs/rewrite/st-compatibility-matrix.md`
- RisuAI compatibility matrix: `docs/rewrite/risuai-compatibility-matrix.md`
- Core interfaces: `docs/rewrite/core-interface-design.md`
- Debugging/observability: `docs/rewrite/pipeline-observability.md`
- Rails integration notes: `docs/rewrite/rails-integration-guide.md`

## Installation (this repo)

This repository vendors TavernKit as an embedded gem.

```ruby
# Gemfile
gem "tavern_kit", path: "lib/tavern_kit"
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
    TavernKit::Prompt::Message.new(role: :user, content: "Hi!"),
    TavernKit::Prompt::Message.new(role: :assistant, content: "Hello!"),
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
and app-owned runtime state (`ctx.runtime`) for parity-sensitive fields.

```ruby
require "json"
require "tavern_kit"

risu_preset = JSON.parse(File.read("my_risu_preset.json"))

runtime_input = {
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
    runtime runtime_input
    message "Hello."
  end

payload = plan.to_messages(dialect: :openai)
```

Notes:
- Runtime input accepts string/camelCase keys; it is normalized once at pipeline
  entry. Internal code relies on canonical snake_case symbol keys.
- `variables_store` is session-level state; persist it per chat (do not share
  across concurrent chats).

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

## Runtime + VariablesStore (app/pipeline synchronization)

Two pieces of state commonly need to stay in sync between your app and the
pipeline:

- `ctx.runtime`: application-owned, per-build snapshot (chat indices, toggles,
  metadata). Set once at pipeline entry; must not be replaced mid-pipeline.
- `ctx.variables_store`: application-owned, session-level store (ST `var` +
  `globalvar`, plus RisuAI extensions). Persist it across turns within a chat.

See `docs/rewrite/core-interface-design.md` for the full contract and
`docs/rewrite/rails-integration-guide.md` for recommended persistence patterns.

## Debugging / Strict mode

- `strict true` is intended for tests/debugging (fail-fast on warnings).
- `instrumenter TavernKit::Prompt::Instrumenter::TraceCollector.new` enables
  detailed stage traces and is meant for development only.

See `docs/rewrite/pipeline-observability.md`.

## Development (embedded gem)

```sh
cd lib/tavern_kit && bin/setup
cd lib/tavern_kit && bundle exec rake test
```

## License

MIT. See `lib/tavern_kit/LICENSE.txt`.
