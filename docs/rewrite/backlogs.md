# Backlogs (Out of Scope for Rewrite Plan)

This file tracks "nice to have" work that is intentionally **out of scope** for
the current TavernKit rewrite plan. These items may be valuable for downstream
apps, but they are not required to ship the rewritten core/library.

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
  using `directives` + runtime synchronization.

## Regex Timeouts (Not Planned)

We intentionally do **not** implement regex timeouts in the rewrite plan.
Instead, we focus on basic, predictable guardrails (pattern length / input size
limits and strict-mode error policy) to mitigate common ReDoS risks without
introducing global or thread-sensitive behavior.

