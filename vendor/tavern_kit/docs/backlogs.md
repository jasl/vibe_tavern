# Backlogs (Out of Scope)

This file tracks "nice to have" work that is intentionally **out of scope** for
the core TavernKit gem deliverable. These items may be valuable for downstream
apps, but they are not required to ship the library.

## CLI / Tools (Deferred)

- Add `exe/tavern_kit` developer tooling:
  - validate/extract/convert/embed character cards
  - prompt preview
  - lore test / scan preview
- Fixtures must be hand-authored (no copying from ST/RisuAI repos).

## UI Directives + Examples (Deferred)

TavernKit does not ship a UI, but downstream apps may want to implement a
RisuAI-like "interactive chat" experience (buttons, code blocks, file cards,
etc.) without introducing UI/HTML into model-bound prompt building.

- Display-bound parsing helper (RisuAI layer), e.g. `RisuAI::UI.parse(text, ...)`
  returning `{ text:, directives: [...] }` (no HTML).
- Model-bound sanitization / separation helpers (Core/RisuAI) to ensure UI does
  not leak into prompt output (optionally preserve placeholders for post-pass).
- Hand-authored examples / PoC showing an interactive guide + VN-like branching
  using `directives` + context synchronization.

## Format Support (Deferred)

TavernKit currently focuses on extracting the prompt-building JSON and exposing
assets lazily; downstream apps decide how to store/import assets.

- CHARX container export (writing `.charx` zip archives).
- RisuAI off-spec card import (OldTavernChar) as an optional RisuAI extension.
- `.risum` module import/export.
- External lorebook importers (NovelAI / Agnai / other apps) via a pluggable
  importer interface (low priority).

## RisuAI Parity Extensions (Deferred)

- Full tokenizer suite parity (multiple tokenizers) beyond the Core pluggable
  token estimator interface.
- Plugin system / Lua hooks (explicitly app-owned in this repo).
- Optional adapters for UI/DB/network trigger effects (TavernKit stays prompt-building-focused).

## Context Data Store Unification (Deferred)

- Evaluate unifying `context.metadata` / `context.toggles` into store-like,
  read-only scopes (currently plain Hashes by design).

## Regex Timeouts (Not Planned)

We intentionally do **not** implement regex timeouts in the rewrite plan.
Instead, we focus on basic, predictable guardrails (pattern length / input size
limits and strict-mode error policy) to mitigate common ReDoS risks without
introducing global or thread-sensitive behavior.
