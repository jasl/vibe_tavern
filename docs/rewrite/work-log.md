# Work Log (Rails Rewrite + TavernKit Integration)

This is a running, append-only record of changes made while integrating
TavernKit into the Rails rewrite. It answers:
- What changed?
- Why did we do it?
- Which commit(s) introduced it?

Guidelines:
- Add new entries at the top.
- Prefer decisions + behavior changes over mechanical refactors.
- Link to the smallest set of commits that tell the story.

---

## 2026-02-03

- Liquid-based macros foundation (app-owned, for `TavernKit::VibeTavern`)
  - Add Liquid dependency: `88dff88`
  - Add design/reference doc: `0cdd299`
  - Implement `LiquidMacros` with `var/global` drops + write tags (`setvar`, `incvar`, etc) + tests: `c095242`
  - Add ST-style escaped braces support and blank-line whitespace stripping + docs/tests: `ede75f0`
  - Add optional app-layer user input preprocessing toggle (default OFF): `29424df`
    - Standard toggle: `runtime[:toggles][:expand_user_input_macros]`
    - Rationale: keep prompt building deterministic and avoid implicit side effects unless explicitly enabled.
  - Pin Liquid assigns contract (`Assigns.build(ctx)`) + tests: `aa2f92f`
  - Add Liquid P0 filters (deterministic RNG + time helpers) + docs/tests: `9b9ba98`
  - Fix Liquid runtime seed wiring; add `render_for(ctx, ...)` helper + tests: `f028797`
  - Add `hash` alias for `hash7`; clarify that `history` is not exposed yet: `84f6068`
  - Add `system_template` (Liquid) to VibeTavern pipeline (optional system block) + tests/docs: `b192c51`
  - Extend VibeTavern pipeline assembly:
    - deterministic default system block from character/user (when no override is set)
    - post-history `system` block (`post_history_instructions` or `post_history_template`)
    - explicit disable semantics via `meta :system_template, nil` / `meta :post_history_template, nil`
    - tests/docs: `6c376cd`
  - Harden Liquid rendering for app-owned macros:
    - add conservative Liquid resource limits + max template size guardrail
    - document runtime.toggles key normalization contract and lock with tests
    - commits: `8b5d2dd`

## 2026-02-02

- Rails rewrite docs baseline
  - Add integration guide: `8833a28`
  - Add integration checklist (models/services/tests only; no UI): `1f7dedd`
  - Improve integration guide for app-owned pipeline usage: `279d6ff`
  - Add rewrite docs index: `218591b`

- App-owned pipeline baseline (`TavernKit::VibeTavern`)
  - Introduce a minimal pipeline (history + user message -> `Prompt::Plan`): `c77b138`
  - Document the pipeline contract (inputs/outputs/semantics): `37f2b4c`
  - Update rewrite docs to make `VibeTavern` the default pipeline for integration examples: `c6d382f`, `1e20282`

- Repo organization / hygiene
  - Move vendored gems under `vendor/` (so the app can treat them as embedded gems): `c0e9662`
  - Remove obsolete `rake test:gate` task (legacy wave-era gate): `6c1be8f`
  - Consolidate rewrite docs and remove wave terminology where it leaked into docs: `12afed3`, `851e46a`

- Gem-level hardening + maintainability (selected highlights)
  - Add ZIP safety regression tests: `62affb3`
  - Harden PNG parsing limits for untrusted text chunks: `2fd3490`
  - Add `RegexSafety` input-size guardrails and apply to regex-heavy subsystems: `aeb5d01`, `1cea647`, `d42450e`, `43ff6bb`
  - Rename/migrate chat variable storage to `VariablesStore` (and remove old aliases): `891cc74`, `66d45ae`
