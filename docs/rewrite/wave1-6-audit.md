# Wave 1-6 Audit (2026-02-02)

This is a "did we actually ship what the roadmap promised?" audit across Waves 1-6.
It is intentionally operational: what exists, what tests prove it, and where the
explicit non-goals/backlogs live.

References:
- Roadmap: `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md`
- ST reference: `resources/SillyTavern` @ `bba43f332`
- RisuAI reference: `resources/Risuai` @ `b8076cae`

## Gates (green)

- Gem: `cd lib/tavern_kit && bundle exec rake` (tests + rubocop)
  - 621 runs, 0 failures, 0 errors, 0 skips
  - Coverage (SimpleCov): ~86.8% line / ~59.9% branch (snapshot)
- Wave 5 gate: `cd lib/tavern_kit && bundle exec rake test:wave5`
- App CI: `bin/ci`
- Style: `bin/rubocop`
- EOF lint: `ruby bin/lint-eof`

## Wave 1 (Core foundations)

Delivered:
- Character/CharacterCard + CCv2/CCv3 parsing/export
- PNG metadata read/write (CCv2 `chara`, CCv3 `ccv3`)
- Prompt basics (Pipeline/DSL/Plan/Context/Block/Message)
- Text PatternMatcher
- Core Coerce/Utils/Constants/Errors

Evidence:
- Unit tests: `lib/tavern_kit/test/tavern_kit/*_test.rb`
  - Cards/PNG: `lib/tavern_kit/test/tavern_kit/character_card_test.rb`,
    `lib/tavern_kit/test/tavern_kit/png/*_test.rb`
  - Prompt core: `lib/tavern_kit/test/tavern_kit/prompt/*_test.rb`
  - Pattern matcher: `lib/tavern_kit/test/tavern_kit/text/pattern_matcher_test.rb`
- Conformance: `lib/tavern_kit/test/conformance/ccv2_conformance_test.rb`,
  `lib/tavern_kit/test/conformance/ccv3_conformance_test.rb`

Intentional divergences vs legacy gem:
- Core parsing APIs are Hash-only; file formats are handled via `TavernKit::Ingest`.
- No default pipeline; platform entry points are `TavernKit::SillyTavern.build` and `TavernKit::RisuAI.build`.

## Wave 2 (Interfaces + data + ST config)

Delivered:
- Core interfaces: Preset/Lore/Macro/Hook/Injection protocols
- Core Lore data: ScanInput/Book/Entry/Result
- Core implementations: ChatHistory, VariablesStore, TokenEstimator, TrimReport, Trace/Instrumenter
- Ingest (PNG/APNG/BYAF/CHARX) bundle API with tmp lifecycle
- ST config layer: Preset/Instruct/ContextTemplate (Handlebars story_string; ST macros preserved)

Evidence:
- Interface/data tests:
  - `lib/tavern_kit/test/tavern_kit/preset/base_test.rb`
  - `lib/tavern_kit/test/tavern_kit/lore/*_test.rb`
  - `lib/tavern_kit/test/tavern_kit/chat_history_test.rb`
  - `lib/tavern_kit/test/tavern_kit/variables_store_test.rb`
  - `lib/tavern_kit/test/tavern_kit/token_estimator_test.rb`
  - `lib/tavern_kit/test/tavern_kit/trim_report_test.rb`
  - `lib/tavern_kit/test/tavern_kit/prompt/trace_test.rb`
- Ingest + archive guardrails:
  - `lib/tavern_kit/test/tavern_kit/ingest/ingest_test.rb`
  - `lib/tavern_kit/test/tavern_kit/archive/zip_reader_test.rb`
- ST config tests:
  - `lib/tavern_kit/test/tavern_kit/silly_tavern/preset_test.rb`
  - `lib/tavern_kit/test/tavern_kit/silly_tavern/instruct_test.rb`
  - `lib/tavern_kit/test/tavern_kit/silly_tavern/context_template_test.rb`

## Wave 3 (ST lore + macros)

Delivered:
- ST World Info / lore engine (keyword + JS regex + timed effects + recursion + budget)
- ST Macro engines (V1 legacy + V2 MacroEngine-like), packs, preprocessors, invocation/env
- ExamplesParser + ExpanderVars

Evidence:
- Unit tests:
  - `lib/tavern_kit/test/tavern_kit/silly_tavern/lore/*_test.rb`
  - `lib/tavern_kit/test/tavern_kit/silly_tavern/macro/**/*_test.rb`
  - `lib/tavern_kit/test/tavern_kit/silly_tavern/examples_parser_test.rb`
  - `lib/tavern_kit/test/tavern_kit/silly_tavern/expander_vars_test.rb`
- Characterization anchors (with upstream references in file headers):
  - `lib/tavern_kit/test/characterization/st_macros_test.rb`
  - `lib/tavern_kit/test/characterization/st_world_info_test.rb`

## Wave 4 (Core output infra + ST middleware chain)

Delivered:
- Core: Trimmer + Dialects (OpenAI/Anthropic/Text + others), MaxTokens middleware guardrails
- ST: 9-stage middleware chain, HookRegistry, InjectionRegistry, GroupContext, full `SillyTavern.build` entry
- Parity-critical ST behaviors: doChatInject ordering/depth, continue+continue_prefill displacement, PromptManager-ish grouping, group activation contracts

Evidence:
- Guardrails suite (Wave 4 contracts):
  - `lib/tavern_kit/test/characterization/wave4_*_contract_test.rb`
- Integration:
  - `lib/tavern_kit/test/integration/silly_tavern_build_test.rb`
- Dialects/trimmer tests:
  - `lib/tavern_kit/test/tavern_kit/prompt/dialects_test.rb`
  - `lib/tavern_kit/test/tavern_kit/trimmer_test.rb`

Contracts:
- `docs/rewrite/wave4-contracts.md`

## Wave 5 (RisuAI parity: prompt building)

Delivered:
- RisuAI runtime contract (`ctx.runtime`), CBS engine + macros + env
- Lorebook engine + decorator parser
- Template cards, regex scripts, triggers (prompt-building-safe effects)
- Memory integration surface (interface + middleware hooks; algorithms app-owned)
- RisuAI pipeline + `RisuAI.build`

Evidence:
- Characterization anchors (with upstream references in file headers):
  - `lib/tavern_kit/test/characterization/risuai_cbs_test.rb`
  - `lib/tavern_kit/test/characterization/risuai_lorebook_test.rb`
  - `lib/tavern_kit/test/characterization/risuai_regex_scripts_test.rb`
  - `lib/tavern_kit/test/characterization/risuai_triggers_test.rb`
- Integration:
  - `lib/tavern_kit/test/integration/risuai_build_test.rb`
  - `lib/tavern_kit/test/integration/risuai_memory_test.rb`

Policy (by design):
- UI/DB/network I/O macros/effects are deferred; app layer injects state via runtime metadata/adapters.

## Wave 6 (Docs + hardening + global review)

Delivered:
- Docs:
  - `docs/rewrite/st-compatibility-matrix.md`
  - `docs/rewrite/risuai-compatibility-matrix.md`
  - `docs/rewrite/rails-integration-guide.md`
  - `docs/rewrite/pipeline-observability.md`
  - `docs/rewrite/wave6-audit.md`
- Safety/perf helpers:
  - `TavernKit::RegexSafety`, `TavernKit::LRUCache`, `TavernKit::JsRegexCache`
- Large-file splits for maintainability (behavior preserved)

Evidence:
- Unit tests:
  - `lib/tavern_kit/test/tavern_kit/regex_safety_test.rb`
  - `lib/tavern_kit/test/tavern_kit/lru_cache_test.rb`
  - `lib/tavern_kit/test/tavern_kit/js_regex_cache_test.rb`

## Cleanliness checks (repo hygiene)

- No skipped tests in the gem test suite.
- No TODO/FIXME markers across `lib/tavern_kit` and `docs/`.
- RuboCop clean for both the Rails app and the embedded gem.

## Explicit non-goals / backlogs

Tracked in `docs/rewrite/backlogs.md`:
- CLI tooling
- UI directives/examples (RisuAI-like presentation parsing)
- Regex timeouts (explicitly not planned; use size guardrails instead)
