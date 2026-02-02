# Architecture (Core + Platform Layers)

TavernKit is a CPU-bound prompt builder. It parses/normalizes supported inputs,
expands macros, activates lore, performs prompt injection and trimming, and
produces a deterministic `Prompt::Plan` that can be converted into provider
"dialect" message payloads.

TavernKit is not a UI framework, a persistence layer, or a provider client.

## Three Layers

```
TavernKit (Core)
├── Value objects (Character, Lore::*, Prompt::*)
├── Pipeline framework (Pipeline, Middleware::Base, Context, DSL)
├── Interface protocols (Lore::Engine::Base, Macro::Engine::Base, etc)
├── Platform-agnostic utilities (TokenEstimator, Trimmer, Dialects, stores)
└── Ingest (PNG/APNG/BYAF/CHARX) -> Bundle (character + optional assets)

TavernKit::SillyTavern
├── ST preset/instruct/template config
├── ST lore engine + macro engines
└── ST middleware chain + build() convenience

TavernKit::RisuAI
├── CBS engine + macros
├── Lorebook engine + decorators
├── Template cards / regex scripts / triggers
└── RisuAI middleware chain + build() convenience
```

## Key Rules

- Core must not contain SillyTavern/RisuAI special-casing.
- Redundancy is allowed in platform layers. When behaviors can diverge in the
  future, prefer two implementations over "almost-the-same" helpers.
- Tolerant at external input boundaries; strict/debug modes exist for tests and
  development-time failure localization.

## State Model (App ↔ Pipeline Sync)

Two types of state matter:

- `variables_store`: persisted, session-level mutable state (ST `var/globalvar`,
  RisuAI scriptstate bridges). Typically one per chat.
- `runtime`: per-build immutable snapshot injected by the app (chat indices,
  metadata/toggles/conditions, etc). Do not persist; derive per request/build.

## I/O Boundaries

- Core parsing APIs are Hash-only (e.g. `CharacterCard.load_hash`).
- File formats are handled by `TavernKit::Ingest`, which returns an
  `Ingest::Bundle` and owns tmp lifecycle via `Ingest.open(path) { |bundle| ... }`.
- ZIP safety for BYAF/CHARX is enforced by `Archive::ZipReader`.
- PNG text-chunk parsing enforces size limits for untrusted metadata chunks.

See:
- Core interfaces: `lib/tavern_kit/docs/core-interface-design.md`
- Contracts: `lib/tavern_kit/docs/contracts/prompt-orchestration.md`
- Security/performance notes: `lib/tavern_kit/docs/security-performance-audit.md`

