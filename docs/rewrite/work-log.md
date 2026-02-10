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

## 2026-02-04

- Tool calling eval hardening + guardrails
  - Add scenario-based OpenRouter eval suite (`OPENROUTER_SCENARIOS`) + failure sample paths in the report table: `d3f0aaf`
  - Make tool argument/output size limits context-configurable (`max_tool_args_bytes`, `max_tool_output_bytes`) and document them: `d3f0aaf`
  - Add test coverage for context denylist masking (tools not exposed + execution blocked): `a1fc3a0`
  - Add context-injected request overrides + tool_choice (provider knobs without lower-layer hacks) and document/test them: `a2cb1dd`
  - Doc: record deferred provider quirks (DeepSeek reasoner `reasoning_content`, Gemini/Claude adapters) as opt-in transforms: `2b612aa`

## 2026-02-03

- Tool calling design decisions (PoC)
  - Record locked-in decisions (workspace model, user-confirmed facts, provider strategy, plan.llm_options): `74acfad`
  - Add DB-free tool-calling loop harness + offline tests + optional OpenRouter eval script: `677f3e9`
  - Support `llm_options(...)` in the prompt DSL (for tools/request-level features): `27f650f`
  - Refactor embedded `simple_inference` to a protocol-based structure (OpenAI-compatible stays default): `08dd945`
  - Doc: `docs/research/vibe_tavern/tool-calling.md`

- Liquid-based macros foundation (app-owned, for `TavernKit::VibeTavern`)
  - Add Liquid dependency: `88dff88`
  - Add design/reference doc: `0cdd299`
  - Implement `LiquidMacros` with `var/global` drops + write tags (`setvar`, `incvar`, etc) + tests: `c095242`
  - Add ST-style escaped braces support and blank-line whitespace stripping + docs/tests: `ede75f0`
  - Add optional app-layer user input preprocessing toggle (default OFF): `29424df`
    - Standard toggle: `context[:toggles][:expand_user_input_macros]`
    - Rationale: keep prompt building deterministic and avoid implicit side effects unless explicitly enabled.
  - Pin Liquid assigns contract (`Assigns.build(ctx)`) + tests: `aa2f92f`
  - Add Liquid P0 filters (deterministic RNG + time helpers) + docs/tests: `9b9ba98`
  - Fix Liquid context seed wiring; add `render_for(ctx, ...)` helper + tests: `f028797`
  - Add `hash` alias for `hash7`; clarify that `history` is not exposed yet: `84f6068`
  - Add `system_template` (Liquid) to VibeTavern pipeline (optional system block) + tests/docs: `b192c51`
  - Extend VibeTavern pipeline assembly:
    - deterministic default system block from character/user (when no override is set)
    - post-history `system` block (`post_history_instructions` or `post_history_template`)
    - explicit disable semantics via `meta :system_template, nil` / `meta :post_history_template, nil`
    - tests/docs: `6c376cd`
  - Harden Liquid rendering for app-owned macros:
    - add conservative Liquid resource limits + max template size guardrail
    - document context.toggles key normalization contract and lock with tests
    - commits: `8b5d2dd`
  - Make Liquid strict mode truly fail-fast (undefined variables/filters now raise) + tests: `9931cad`

## 2026-02-02

- Rails rewrite docs baseline
  - Add integration guide: `8833a28`
  - Add integration checklist (models/services/tests only; no UI): `1f7dedd`
  - Improve integration guide for app-owned pipeline usage: `279d6ff`
  - Add rewrite docs index: `218591b`

- App-owned pipeline baseline (`TavernKit::VibeTavern`)
  - Introduce a minimal pipeline (history + user message -> `PromptBuilder::Plan`): `c77b138`
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
