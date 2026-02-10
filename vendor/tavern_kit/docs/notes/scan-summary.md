> [!IMPORTANT]
> Historical / discovery document (2026-01-29). This file is kept for context but may be outdated.
> Current source of truth:
> - `docs/README.md`
> - `docs/compatibility/sillytavern.md`
> - `docs/compatibility/risuai.md`
> - Rails integration docs: `docs/rewrite/rails-integration-guide.md`

# Scan Summary (2026-01-29)

## Project State

### What Exists
- **Rails 8.2 app scaffolding**: Full infrastructure (Puma, Solid Queue/Cache/Cable, Tailwind+DaisyUI, Hotwire, Bun, Propshaft)
- **Active Storage migration**: Only migration committed; no app models/migrations yet
- **Result service**: `app/services/result.rb` with success/failure pattern
- **EasyTalk fork**: `vendor/easy_talk/` with `ActiveModelType` adapter already implemented (`to_type`)
- **TavernKit stub**: `vendor/tavern_kit/` with just version.rb and main entry point (at the time of this scan)
- **Comprehensive documentation**: `CLAUDE.md`, `docs/`, `.sisyphus/` drafts
- **Test infrastructure**: Minitest, SimpleCov, parallel workers, fixtures dirs created
- **Frontend CSS**: Tailwind config with SillyTavern message styling (`.mes-*`), CJK typography, DaisyUI theme
- **Docker setup**: PostgreSQL with pgvector via compose.dev.yaml
- **CI script**: `bin/ci` using ActiveSupport::ContinuousIntegration (rubocop, bun lint, bundler-audit, brakeman, tests)
- **Queue config**: 3 queues (default, uploads, llm) with configurable concurrency

### What Doesn't Exist Yet
- Application models (Character, Space, Preset, Conversation, Message)
- Database migrations for app entities
- Controllers (API or web)
- TavernKit gem implementation (pipeline, macros, character cards, lore, etc.)
- ActionCable channels
- Stimulus controllers for chat
- Test files (except result_test.rb)

## Key Decisions Already Made

| Decision | Choice | Source |
|----------|--------|--------|
| JSON serialization | Option C: Fork EasyTalk + ActiveModel::Type | `.sisyphus/drafts/` |
| Parity priority | SillyTavern primary, RisuAI secondary/backlog | `docs/notes/overview.md` |
| StoreModel adoption | Rejected | `docs/notes/store-model-evaluation.md` |
| Rails 8.2 `has_json` usage | Useful for flat settings only; cannot replace EasyTalk for nested | `docs/notes/overview.md` |
| EasyTalk fork policy | Allowed; log changes in `FORK_CHANGES.md` | Confirmed in overview |
| API breakage tolerance | Acceptable for better design | Confirmed |
| Data migration | Greenfield; no production data | Confirmed |
| Pipeline modularization | ST-specific pipeline/macros in `TavernKit::SillyTavern` module | Confirmed |
| Testing | Minitest + fixtures; TDD with characterization tests first | `CLAUDE.md` |

## Rails 8.2 Schematized JSON

Location: `resources/rails/activemodel/lib/active_model/schematized_json.rb`

- `has_json` / `has_delegated_json` provides schema-enforced JSON access
- **Flat only**: boolean, integer, string (no nesting)
- Type casting via `ActiveModel::Type.lookup`
- Defaults via `reverse_merge!`, lazy materialization, `before_save` hook
- Unknown keys raise `NoMethodError`
- Good for flat settings/flags, NOT a replacement for EasyTalk

## Reference Architecture (TavernKit)

### Gem Core (framework-agnostic)
- **Data models**: `Data.define` for Character, User, Preset, Instruct, ContextTemplate
- **Character Card**: V2/V3 loading, PNG read/write, version detection, round-trip export
- **Pipeline**: 9-step Rack-like pipeline (Hooks -> Lore -> Entries -> PinnedGroups -> Injection -> Compilation -> MacroExpansion -> PlanAssembly -> Trimming)
- **Macros**: 50+ SillyTavern-compatible macros via V1 (regex) and V2 (parser) engines
- **Lore/World Info**: Keyword matching, token budgeting, recursive scanning, timed effects
- **Output Dialects**: OpenAI, Anthropic, Google, Text (+ others)
- **Registries**: MacroRegistry, InjectionRegistry, HookRegistry, VariablesStore

### Playground Integration Pattern
- **Adapters**: CharacterAdapter, ParticipantAdapter, PresetResolver, LoreBooksResolver, MessageHistory
- **PromptBuilder service**: Main entry point converting Rails models -> TavernKit domain -> Plan
- **EasyTalkCoder**: Custom `serialize` coder for JSONB columns
- **ConversationSettings**: Nested EasyTalk schemas with `x-ui`/`x-storage` extensions

## Execution Plan Summary

5 waves, 20 tasks (from `.sisyphus/plans/vibe-tavern-rewrite.md`):

1. **Foundation** (3 tasks): Port tests, gem models, EasyTalk docs
2. **Character Cards** (3 tasks): V2/V3 loading, PNG I/O, basic macros
3. **Pipeline** (4 tasks): Step arch, core steps, presets, output dialects
4. **Advanced + Rails** (5 tasks): Full macros, World Info, trimming, EasyTalk integration, core models
5. **Integration + Frontend** (5 tasks): Conversation/Message, PromptBuilder, API, ActionCable, Stimulus UI

Critical path: Task 1 -> 4 -> 7 -> 8 -> 10 -> 17 -> 19

## Questions Identified During Scan

See separate section below.
