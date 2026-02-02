> [!IMPORTANT]
> Historical / discovery document (2026-01-28). This file is kept for context but may be outdated.
> Current source of truth:
> - `lib/tavern_kit/docs/README.md`
> - `lib/tavern_kit/docs/compatibility/sillytavern.md`
> - `lib/tavern_kit/docs/compatibility/risuai.md`
> - Rails integration docs: `docs/rewrite/rails-integration-guide.md`

# Vibe Tavern Rewrite - Discovery Overview (2026-01-28)

## Goals (from user request)
- Eliminate inconsistencies and redundancy accumulated during "vibe coding".
- Simplify implementations for readability and lower complexity.
- Maximize modularity and reuse (this repo as OSS library + demo; next project will reuse source).
- Redesign architecture + API based on Playground usage of TavernKit.
- Use Rails 8.2 + Ruby 4.0 best practices, especially safe JSON access in models.
- Re-check and align behavior with SillyTavern and RisuAI.
- Remove potential bugs, especially frontend interaction + style inconsistencies.

## Repo Sources of Truth
- Constraints + architecture rules: `CLAUDE.md`
- Local agent prompts/skills: `.claude/`
- Legacy references: `resources/tavern_kit/` (gem) and `resources/tavern_kit/playground/` (Rails app)
- Rails source for 8.2 schematized JSON: `resources/rails/activemodel/lib/active_model/schematized_json.rb`
- Other references: `resources/SillyTavern/`, `resources/RisuAI/`, `resources/fizzy/`, `resources/rails_ai_agents/`
- Half-finished drafts/plans: `.sisyphus/`

## Quick Scan Findings
- Rails is already pinned to edge 8.2 in `Gemfile`; Ruby is 4.0.1 (see `.ruby-version`).
- `easy_talk` and `tavern_kit` are vendored as path gems under `lib/`.
- `lib/tavern_kit` appears stub-like and is expected to be fully rewritten.
- Playground uses `serialize` with a custom `EasyTalkCoder` to map JSONB columns.
- Rails 8.2 schematized JSON (`has_json` / `has_delegated_json`) is present in the local Rails source.

## Rails 8.2 Schematized JSON (from local Rails source)
- `has_json` wraps JSON attributes with a schema-enforced accessor.
- Supported types are **boolean / integer / string only**; **no nesting**.
- Type casting uses `ActiveModel::Type.lookup`.
- Defaults are applied via `reverse_merge!`, with lazy materialization and a `before_save` hook.
- Unknown keys raise `NoMethodError` (schema-enforced).
- This is useful for flat settings/flags but does **not** replace nested EasyTalk schemas.

## Known Constraints / Guardrails
- Use smallest architectural tool: model -> query -> service -> presenter.
- Use Minitest + fixtures; avoid mixing refactors with behavior changes.
- Avoid new dependencies unless necessary; keep diffs small.

## Open Questions (needs confirmation)
1. SillyTavern vs RisuAI parity: **Confirmed** — SillyTavern is the primary source of truth for conflicts.
2. Target SillyTavern version: **Confirmed** — align to current SillyTavern; use `resources/SillyTavern` snapshot as reference (no commit pin).
3. JSON strategy: **Needs verification** — Rails 8.2 `has_json` currently documents **no nesting** (boolean/integer/string only). We'll verify in `resources/rails` and determine whether EasyTalk schemas can be mapped or require a hybrid.
4. EasyTalk fork: **Confirmed** — we can directly modify `lib/easy_talk/` and keep local change notes for later upstream diffing.
5. API breakage tolerance: **Confirmed** — no hard compatibility constraints; breaking changes are acceptable if the result is better.
6. Data migration: **Confirmed** — greenfield rewrite, no production data migration required.
7. Frontend scope: **Confirmed** — UI can be significantly reshaped, but must be tested for correct rendering/interaction.
8. Pipeline modularization: **Confirmed** — SillyTavern pipeline/macros should live under `TavernKit::SillyTavern`.

## Scope Updates (2026-01-29)
- RisuAI parity includes **memory system integration**; tokenizer parity is
  interface-first, full tokenizer suite deferred.
- Plugins/Lua hooks are **lowest priority**; `.risum` modules are **deferred**
  (not part of this batch).
- Data Bank / vector matching are **interfaces only** in TavernKit; I/O stays
  in the application layer.
- ST/RisuAI-specific fields live in `extensions`; platform layers interpret them.
- Core `Prompt::Message` should reserve optional multimodal/metadata fields.

## Next Steps (proposed)
- Deep-dive `resources/tavern_kit/ARCHITECTURE.md` and Playground models/services.
- Extract a parity checklist against SillyTavern/RisuAI for critical behaviors.
- Draft a JSON strategy doc that maps each settings schema to EasyTalk vs `has_json`.
- Convert `.sisyphus/` drafts into long-lived docs/backlogs in `lib/tavern_kit/docs/`.

## Related Notes
- StoreModel evaluation: `lib/tavern_kit/docs/notes/store-model-evaluation.md`
  - Current recommendation: keep EasyTalk as schema source; do not adopt StoreModel as primary.
- EasyTalk ActiveModel::Type adapter: `lib/tavern_kit/docs/notes/easy_talk-active_model_type.md`
- ST/RisuAI parity checklist: `lib/tavern_kit/docs/notes/st-risuai-parity.md`

## Consolidated from .sisyphus (Backlog Drafts)
- **JSON strategy**: Option C is the chosen direction (fork EasyTalk + ActiveModel::Type integration; preserve nested schemas).
- **Rewrite phases (proposed)**:
  1. Gem foundation: core models + Character Card V2/V3 + PNG read/write + basic macros.
  2. Prompt pipeline: middleware architecture + Prompt Manager + output dialects.
  3. Advanced features: full macro pack + World Info engine + context trimming.
  4. Rails integration: EasyTalk wiring + core models + PromptBuilder + API.
  5. Frontend/streaming: ActionCable + UI import/export + settings.
- **Parity policy**: SillyTavern primary, RisuAI secondary (notes captured, implementation deferred).
- **RisuAI status**: documentation + characterization scaffolding exists; kept as backlog until ST parity is stable.
- **Characterization scaffolding**: ST/RisuAI placeholder tests exist and are currently skipped; they will be enabled as each module is implemented.
