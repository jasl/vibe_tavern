# Draft: Vibe Tavern Rewrite Architecture

## Requirements (confirmed)
- Rewrite goal: eliminate inconsistencies accumulated during "vibe coding"; unify code style; remove redundancy.
- Simplify implementations: improve readability; reduce complexity.
- Maximize modularity and reuse: this repo will serve as OSS library + demo; next project will reuse by source copy (not dependency).
- Use Ruby/Rails best practices; redesign architecture + API based on how Playground uses TavernKit.
- Prefer Rails 8.2 + Ruby 4.0 modern features, especially safe access to JSON-serialized model fields.
- Re-check and align behavior with SillyTavern + RisuAI.
- Remove potential bugs, especially frontend interaction + style inconsistencies.
- References live under `resources/`.

## Technical Decisions (tentative / to validate)
- Evaluate replacing/augmenting `easy_talk` + custom Rails coder approach with Rails 8.2 "schematized json" (PR 56258 + follow-ups).
- Prefer not to modify `easy_talk` to stay close to upstream; allowed to fork if required for correctness.
- TavernKit: keep SillyTavern compatibility (macros/pipeline) but isolate it into a dedicated `SillyTavern` module.
- Parity priority decision: **SillyTavern is the primary source of truth** when outputs conflict.

## Research Findings
- Repo stack confirmed:
  - Rails is already pinned to edge `rails/rails` (8.2.0.alpha) via `Gemfile`.
  - Ruby version is `4.0.1` via `.ruby-version`.
  - `easy_talk` is vendored via `gem "easy_talk", path: "lib/easy_talk"`.
  - `tavern_kit` is vendored via `gem "tavern_kit", path: "lib/tavern_kit"`.
- Current embedded gem `lib/tavern_kit` is effectively a stub (`lib/tavern_kit/lib/tavern_kit.rb`).
- Legacy/reference TavernKit implementation + docs exist under `resources/tavern_kit/` (notably `resources/tavern_kit/ARCHITECTURE.md`).
- Current target "Playground" reference uses **jsonb columns + `serialize` with a custom `EasyTalkCoder`** pattern:
  - `resources/tavern_kit/playground/app/models/character.rb` uses:
    - `serialize :data, coder: EasyTalkCoder.new(TavernKit::Character::Schema)`
    - `serialize :authors_note_settings, coder: EasyTalkCoder.new(ConversationSettings::AuthorsNoteSettings)`
  - `resources/tavern_kit/playground/app/models/space.rb` uses:
    - `serialize :prompt_settings, coder: EasyTalkCoder.new(ConversationSettings::SpaceSettings)`
  - `resources/tavern_kit/playground/app/models/preset.rb` uses:
    - `serialize :generation_settings, coder: EasyTalkCoder.new(ConversationSettings::LLM::GenerationSettings)`
    - `serialize :preset_settings, coder: EasyTalkCoder.new(ConversationSettings::PresetSettings)`
  - `resources/tavern_kit/playground/app/models/space_membership.rb` uses:
    - `serialize :settings, coder: EasyTalkCoder.new(ConversationSettings::ParticipantSettings)`
  - The coder itself is defined at `resources/tavern_kit/playground/app/models/concerns/easy_talk_coder.rb`.
- Playground reference schema has many jsonb columns with defaults and comments (see `resources/tavern_kit/playground/db/schema.rb` and `resources/tavern_kit/playground/db/migrate/20260108045602_init_schema.rb`).
- Playground reference includes an atomic jsonb update/delete pattern for macro variables store:
  - `resources/tavern_kit/playground/app/models/conversations/variables_store.rb` uses SQL `jsonb_set(COALESCE(...), ...)` and jsonb `-` operator.

- Rails 8.2 edge introduces **schema-enforced JSON access** via `ActiveModel::SchematizedJson` (`has_json` / `has_delegated_json`):
  - Code (edge main): `https://raw.githubusercontent.com/rails/rails/main/activemodel/lib/active_model/schematized_json.rb`
  - PR: `https://github.com/rails/rails/pull/56258`
  - Weekly highlight: `https://rubyonrails.org/2025/12/5/this-week-in-rails`
  - API summary:
    - `has_json :settings, key: true, count: 10, greeting: "Hello", mode: :string`
    - `has_delegated_json :flags, beta: false, staff: :boolean` (also defines `beta`, `beta?`, `beta=` on the model)
  - Behavior details (from the actual implementation):
    - Supported types: **boolean / integer / string only**; **no nesting**.
    - Type casting uses `ActiveModel::Type.lookup(...).cast(value)`.
    - Defaults are applied with `reverse_merge!` into the underlying hash; accessor is created fresh each call (no memoization, reload-safe).
    - Default materialization is effectively **lazy**: column can be `nil` until accessor is first accessed; `before_save` hook forces default application before persist.
    - Schema keys are enforced: bulk assign calls per-key setters; unknown keys raise `NoMethodError`.
    - Predicate `key?` is implemented as `present?` on stored value (presence semantics).
  - Implication: `has_json` can improve safety for **flat settings/flags** and UI-submitted string casting, but cannot replace nested EasyTalk schemas.

- Playground settings schema pack is EasyTalk-based and already extends EasyTalk substantially:
  - `resources/tavern_kit/playground/app/models/conversation_settings/base.rb` defines:
    - `ConversationSettings::Base` (includes `EasyTalk::Model`)
    - `NestedSchemaSupport` (custom nested schema instances + `to_h` merge)
    - JSON Schema extensions `x-ui` and `x-storage` and schema registry.
  - Example composition:
    - `resources/tavern_kit/playground/app/models/conversation_settings/space_settings.rb` nests preset/world_info/memory/rag/i18n schemas.
    - `resources/tavern_kit/playground/app/models/conversation_settings/preset_settings.rb` is a large **flat** schema (strings/booleans/integers) and is a candidate for `has_json`-style semantics *if* we can avoid duplicating schema definitions.
- (COMPLETED) Codebase scan: EasyTalk/JSON coders used in Character, Space, Preset, SpaceMembership models with nested schema support.
- (COMPLETED) Playground scan: TavernKit consumed via `PromptBuilder` service using adapter pattern (`PromptBuilding::*Adapter`).
- (COMPLETED) Rails 8.2 schematized JSON: Supports flat boolean/integer/string only. No nesting planned. Cannot replace EasyTalk for complex schemas.

## JSON Serialization Strategy (DECIDED: Option C)

**CHOSEN: Option C - Fork EasyTalk to integrate with Rails 8.2**
- Bridge EasyTalk's schema definition with Rails 8.2 type system
- Unified approach with modern Rails primitives
- Will maintain as vendored gem at `lib/easy_talk`
- Can contribute improvements back upstream if appropriate

**Implementation approach**:
1. Keep vendored `lib/easy_talk` as base
2. Add Rails 8.2 `ActiveModel::Type` integration for type casting
3. Add `has_json`-style accessor generation where appropriate
4. Maintain full nested schema support (EasyTalk's strength)
5. Add `x-ui` and `x-storage` JSON Schema extensions for UI generation

## Scope Boundaries
- INCLUDE: architectural redesign + refactor/rewrite to match frozen feature set from `resources/tavern_kit` and `resources/tavern_kit/playground`.
- EXCLUDE: net-new product features beyond the frozen target set (unless required for parity/bugfix).

## Decisions Finalized
- **SillyTavern/RisuAI parity**: SillyTavern is primary source of truth, RisuAI secondary
- **Rails version policy**: Edge (8.2.0.alpha) is fine - Gemfile already pins to rails/rails main
- **Testing strategy**: Minitest + Characterization Tests - port reference tests, add characterization tests before refactoring
- **JSON Serialization**: Option C - Fork EasyTalk to integrate with Rails 8.2 type system

## Implementation Order (Proposed)

### Phase 1: Foundation
1. TavernKit gem core structure (Data.define models, error hierarchy)
2. Character Card V2/V3 loading/export
3. PNG parser/writer for card extraction
4. Basic macro system (identity, character fields)

### Phase 2: Prompt Pipeline
1. Middleware architecture (Pipeline, Context, Base middleware)
2. Core middleware (Hooks, Lore, Entries, Compilation, PlanAssembly)
3. Preset system with Prompt Manager entries
4. Output dialects (OpenAI, Anthropic)

### Phase 3: Advanced Features
1. Full macro pack (time, random, variables)
2. World Info engine (keywords, budget, recursion, timed effects)
3. Context trimming
4. Injection registry, Hook registry

### Phase 4: Rails Integration
1. EasyTalk setup + EasyTalkCoder
2. Core models (Character, Space, Preset, Conversation)
3. PromptBuilder service with adapters
4. API controllers

### Phase 5: Frontend + Streaming
1. ActionCable for LLM streaming
2. Stimulus controllers for chat UI
3. Character card import/export UI
4. Settings management UI
