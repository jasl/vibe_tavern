# Implementation Audit (2026-02-02)

This is a "did we actually ship what our docs claim?" audit of the embedded
`lib/tavern_kit/` gem.

It is intentionally operational: what exists, what tests prove it, and where
explicit non-goals/backlogs live.

References:
- Pinned reference sources: `docs/reference-sources.md`
- Contracts: `docs/contracts/prompt-orchestration.md`
- Compatibility matrices:
  - SillyTavern: `docs/compatibility/sillytavern.md`
  - RisuAI: `docs/compatibility/risuai.md`
- Rails integration: `docs/rewrite/rails-integration-guide.md`

## Gates (green)

- Gem: `cd lib/tavern_kit && bundle exec rake` (tests + gem rubocop)
- App CI: `bin/ci`
- Style: `bin/rubocop`
- EOF lint: `ruby bin/lint-eof`

## Core (Platform-agnostic)

Delivered:
- Character/CharacterCard + CCv2/CCv3 parsing/export
- PNG metadata read/write (CCv2 `chara`, CCv3 `ccv3`)
- Prompt framework (Pipeline/DSL/Plan/Context/Block/Message)
- Text PatternMatcher
- Coerce/Utils/Constants/Errors
- Interfaces: Preset/Lore/Macro/Hook/Injection
- Lore data: ScanInput/Book/Entry/Result
- Implementations: ChatHistory, VariablesStore, TokenEstimator, TrimReport, Trace/Instrumenter
- Dialects (OpenAI/Anthropic/Text + others)
- Trimmer
- Ingest (PNG/APNG/BYAF/CHARX) bundle API with tmp lifecycle

Evidence:
- Unit tests: `lib/tavern_kit/test/tavern_kit/**/*_test.rb`
- Conformance: `lib/tavern_kit/test/conformance/ccv2_conformance_test.rb`,
  `lib/tavern_kit/test/conformance/ccv3_conformance_test.rb`
- Integration: `lib/tavern_kit/test/integration/*_test.rb`

Intentional divergences vs the legacy gem:
- Core parsing APIs are Hash-only; file formats are handled via `TavernKit::Ingest`.
- No default pipeline; platform entry points are `TavernKit::SillyTavern.build` and
  `TavernKit::RisuAI.build`.

## SillyTavern Layer

### Config layer

Delivered:
- ST preset/instruct/context-template config objects and importers

Evidence:
- `lib/tavern_kit/test/tavern_kit/silly_tavern/preset_test.rb`
- `lib/tavern_kit/test/tavern_kit/silly_tavern/instruct_test.rb`
- `lib/tavern_kit/test/tavern_kit/silly_tavern/context_template_test.rb`

### Lore + macros

Delivered:
- ST World Info engine (keyword + JS regex + timed effects + recursion + budget)
- ST macro engines (V1 legacy + V2 MacroEngine-like), packs, preprocessors, invocation/env
- ExamplesParser + ExpanderVars

Evidence:
- `lib/tavern_kit/test/tavern_kit/silly_tavern/lore/*_test.rb`
- `lib/tavern_kit/test/tavern_kit/silly_tavern/macro/**/*_test.rb`
- `lib/tavern_kit/test/tavern_kit/silly_tavern/examples_parser_test.rb`
- `lib/tavern_kit/test/tavern_kit/silly_tavern/expander_vars_test.rb`
- Characterization anchors:
  - `lib/tavern_kit/test/characterization/st_macros_test.rb`
  - `lib/tavern_kit/test/characterization/st_world_info_test.rb`

### Prompt orchestration pipeline

Delivered:
- 9-stage middleware chain, HookRegistry, InjectionRegistry, GroupContext
- Parity-critical ST behaviors pinned by contract tests:
  - in-chat injection ordering/depth
  - continue + continue_prefill displacement
  - PromptManager-style grouping
  - group activation strategies and card merging

Evidence:
- Guardrails suite (contracts): `lib/tavern_kit/test/characterization/*_contract_test.rb`
- Integration: `lib/tavern_kit/test/integration/silly_tavern_build_test.rb`
- Prompt infra: `lib/tavern_kit/test/tavern_kit/trimmer_test.rb`,
  `lib/tavern_kit/test/tavern_kit/prompt/dialects_test.rb`

## RisuAI Layer (Prompt building)

Delivered:
- Runtime contract (`ctx.runtime`), CBS engine + macros + environment
- Lorebook engine + decorator parser
- Template cards, regex scripts, triggers (prompt-building-safe effects)
- Memory integration surface (interface + middleware hooks; algorithms app-owned)
- RisuAI pipeline + `RisuAI.build`

Evidence:
- Characterization anchors:
  - `lib/tavern_kit/test/characterization/risuai_cbs_test.rb`
  - `lib/tavern_kit/test/characterization/risuai_lorebook_test.rb`
  - `lib/tavern_kit/test/characterization/risuai_regex_scripts_test.rb`
  - `lib/tavern_kit/test/characterization/risuai_triggers_test.rb`
- Integration:
  - `lib/tavern_kit/test/integration/risuai_build_test.rb`
  - `lib/tavern_kit/test/integration/risuai_memory_test.rb`

Policy (by design):
- UI/DB/network I/O macros/effects are deferred; app layer injects state via runtime metadata/adapters.

## Docs + hardening

Delivered:
- Gem docs home: `docs/README.md`
- Compatibility matrices + deltas + contracts
- Safety/perf helpers: `TavernKit::RegexSafety`, `TavernKit::LRUCache`, `TavernKit::JsRegexCache`
- Large-file splits for maintainability (behavior preserved)

Evidence:
- `lib/tavern_kit/test/tavern_kit/regex_safety_test.rb`
- `lib/tavern_kit/test/tavern_kit/lru_cache_test.rb`
- `lib/tavern_kit/test/tavern_kit/js_regex_cache_test.rb`

## Repo hygiene

- No skipped tests in the gem suite.
- No TODO/FIXME markers across `lib/tavern_kit` and gem docs.
- RuboCop clean for both the Rails app and the embedded gem.

## Explicit non-goals / backlogs

Tracked in `docs/backlogs.md`.
