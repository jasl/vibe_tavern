# TavernKit Gem Rewrite Roadmap

Date: 2026-01-29 (revised)

## Goal

Rewrite `lib/tavern_kit/` to be **functionally >= the original** (`resources/tavern_kit/`),
while surpassing it in architecture, code quality, Ruby style, test coverage,
and SillyTavern/RisuAI spec support.

## Principles

1. **Incremental rewrite** -- reference original, implement from scratch with
   better architecture. Deliver one independent Wave at a time.
2. **Test first** -- extract/write characterization tests before implementation.
   Unlock pending tests as modules land.
3. **Immutable by default** -- value objects use Ruby `Data` or frozen Struct.
   Note: immutability is currently **shallow** (object frozen; nested values may
   still be mutable). We treat all nested values as read-only by convention and
   will tighten this at module boundaries as needed.
4. **Small files** -- 200-400 lines typical, 800 max. Split original large files.
5. **API redesign** -- no backward compatibility constraint. Design for the
   downstream Rails app: clear interfaces, explicit semantics, fail-fast with
   descriptive errors.
6. **Three-layer architecture** -- Core (interfaces + platform-agnostic infra) +
   SillyTavern (ST-specific implementation) + RisuAI (RisuAI-specific).
   See "Architecture" section.
7. **CI gate per Wave** -- all tests green + rubocop clean. Coverage target
   ramps over time (>= 80% by Wave 5).

## Scope Clarifications (2026-01-29 Update)

- **Reference source pins (for parity):**
  - SillyTavern (staging): `resources/SillyTavern` @ `bba43f332`
  - RisuAI: `resources/Risuai` @ `b8076cae`
  - Legacy TavernKit (baseline): `resources/tavern_kit` @ `5e54d324`
  - BYAF spec: `resources/byaf` @ `7ebf2fd`
  - CCv3 spec: `resources/character-card-spec-v3` @ `f3a86af`
  - When updating any reference source, record the new commit hash here to
    keep characterization tests traceable.

- **RisuAI parity scope (this batch):** include **memory system integration**
  (HypaMemory/SupaMemory stage) as part of the RisuAI pipeline. Tokenizer parity
  is acknowledged but will be **interface-first** and can be completed later.
  Acceptance criteria (integration, not I/O):
  - Pipeline can accept memory artifacts (summaries, pinned memories, metadata)
    via Context/hooks and place them into prompt output deterministically.
  - Memory stage participates in budgeting/trimming decisions (via block tags /
    `removable` / priority), without performing retrieval or vector matching.
- **Deferred/low priority:** RisuAI **plugins**, **Lua hooks**, and **.risum
  modules** are **explicitly out of scope for this batch**. Track as Wave 6+
  backlog items.
- **Data Bank / vector matching:** TavernKit stays **prompt-building focused**.
  Provide **interfaces/hooks** for vector results; **I/O + retrieval lives in
  the application layer**.
- **File ingestion:** Core `CharacterCard` parses from a Ruby `Hash` only.
  All on-disk formats are handled by `TavernKit::Ingest`, which returns an
  `Ingest::Bundle` (character + optional extracted files + warnings). Use
  `TavernKit::Ingest.open(path) { |bundle| ... }` to ensure tmp cleanup.
- **BYAF (.byaf) ingest:** `TavernKit::Ingest` maps BYAF (Backyard Archive
  Format) into a CCv2-compatible payload and returns normalized `scenarios`
  hashes. It may extract referenced character images and scenario background
  images into a temp directory for downstream apps to import.
- **CHARX (.charx) ingest:** `TavernKit::Ingest` parses and validates
  `card.json` (CCv3) and extracts `embeded://...` assets into a temp directory.
  Export of CHARX containers is deferred to Wave 6+.
- **RisuAI off-spec card import (OldTavernChar):** defer to **Wave 6+** as a
  **RisuAI extension**. RisuAI can provide a converter that normalizes off-spec
  payloads into CCv2/CCv3 hashes and then calls Core parsing APIs.
- **Platform-specific fields:** ST/RisuAI-only fields should live in
  `extensions` (Core) and be interpreted by the platform layer.
- **Multimodal / tool-calling forward-compat:** Core `Prompt::Message` should
  reserve optional `attachments` and `metadata` fields to avoid future breaking
  changes (images/audio + tool calls/tool results).
  Note: until Dialects are implemented, `Plan#to_messages` fallback returns
  minimal message hashes (role/content/name) and may drop passthrough fields.

## Architecture: Three Layers

```
TavernKit (Core)
├── Value objects & data models (Character, CharacterCard, User, Participant,
│   Lore::Book, Lore::Entry, Lore::Result, Lore::ScanInput, Prompt::*)
├── Pipeline framework (Pipeline, Middleware::Base, Context, DSL)
├── Interface protocols:
│   ├── Lore::Engine::Base (#scan(input) -> Lore::Result)
│   ├── Macro::Engine::Base (#expand(text, environment:) -> String)
│   ├── Macro::Environment::Base (character_name, user_name, get_var/set_var)
│   ├── Macro::Registry::Base (#register(name, handler, **metadata))
│   ├── Preset::Base, HookRegistry::Base, InjectionRegistry::Base
│   └── ChatVariables::Base (scope: :local/:global; extensible by platforms)
├── Platform-agnostic implementations:
│   ├── Dialects (OpenAI, Anthropic, Google, Cohere, AI21, Mistral, XAI, Text)
│   ├── TokenEstimator (pluggable adapters; tiktoken_ruby default, model_hint:)
│   ├── Trimmer (pluggable strategy: :group_order or :priority)
│   ├── ChatHistory::Base + ChatHistory::InMemory
│   └── ChatVariables::InMemory
├── Utilities (Coerce, Utils, Constants, Errors, Png::Parser/Writer)
└── Ingest (file adapters: JSON/PNG/APNG/BYAF/CHARX; tmp extraction bundle)

TavernKit::SillyTavern
├── Config: Preset (40+ ST keys, JSON import), Instruct, ContextTemplate
├── Lore: Engine, DecoratorParser, TimedEffects, KeyList, ScanInput, WorldInfoImporter, EntryExtensions
├── Macro: V1Engine, V2Engine, Registry, Packs, Environment, Invocation
├── Middleware (9 stages): Hooks, Lore, Entries, PinnedGroups, Injection,
│   Compilation, MacroExpansion, PlanAssembly, Trimming
├── Tools: ExamplesParser, ExpanderVars, HookRegistry,
│   InjectionRegistry, GroupContext
└── Pipeline (default 9-stage chain), SillyTavern.build() convenience entry

TavernKit::RisuAI (Wave 5)
├── CBS: Engine, Macros (130+), Environment
├── Lore: Engine, DecoratorParser (30+), ScanInput
├── Memory (Hypa/Supa), RegexScripts, Triggers (v1+v2), TemplateCards
└── Pipeline, RisuAI.build() convenience entry
```

### Layer Responsibilities

**Core** provides:
- Shared value objects that both ST and RisuAI use (Character, Lore::Book, etc.)
- The Pipeline framework itself (middleware orchestration, not any specific stages)
- Interface protocols that ST and RisuAI implement (Lore::Engine::Base, etc.)
- Platform-agnostic infra: Dialects (LLM API formats have nothing to do with
  ST or RisuAI), TokenEstimator (token counting is universal), Trimmer (budget
  enforcement is generic), ChatHistory/ChatVariables (storage abstractions)

**SillyTavern** provides:
- ST-specific configuration formats (Preset with 40+ ST keys, Instruct sequences,
  ContextTemplate with Handlebars story_string)
- ST-specific algorithms (Lore::Engine with ST's keyword/recursion/timed effects,
  Macro::Engine with `{{macro}}` syntax and 50+ built-in ST macros)
- ST-specific middleware chain (14 pinned group slots, FORCE_RELATIVE_IDS,
  FORCE_LAST_IDS, in-chat depth/order/role rules)
- ST-specific tools (ExamplesParser with `<START>` markers)

**RisuAI** provides:
- CBS macro system (`#if`/`#when`/`#each`/`#func`/`#escape`/`#pure`)
- RisuAI decorator syntax (40+ decorators, `@inject_lore`/`@inject_at`)
- Memory system (Hypa/Supa), regex scripts, triggers, template cards
- RisuAI-specific middleware chain

### Key Design Rule

**No ST or RisuAI specifics leak into Core.**

- **Redundancy is allowed in platform layers.** ST and RisuAI often have
  intentionally different semantics. When behaviors diverge, we prefer
  duplicating implementation inside `TavernKit::SillyTavern` and
  `TavernKit::RisuAI` over sharing “almost the same” code that later forces
  hacks or cross-regressions.
  - Reuse Core **interfaces and primitives** (Pipeline, Lore/Macro base
    protocols, Trimmer, TokenEstimator), not platform logic.
  - Avoid `if platform == ...` switches inside Core; Core should be usable by
    multiple concrete implementations without special-casing.

- Exception: `Prompt::Context` is a mutable build workspace and may temporarily
  carry ST-flavored accessors for ergonomics; those should migrate into
  `ctx.metadata` as the ST/RisuAI layers land (see `docs/rewrite/core-interface-design.md`).

- String constants like `"main_prompt"`, `"nsfw"`, `{{char}}` belong in
  `TavernKit::SillyTavern`, never in `TavernKit` root.
- ST's WI position enum (before/after/EMTop/EMBottom/ANTop/ANBottom/atDepth)
  belongs in `SillyTavern::Lore::Engine`, not `Lore::Engine::Base`.
- CBS syntax (`{{#if}}`, `{{#when}}`) belongs in `RisuAI::CBS::Engine`.
- Dialects, TokenEstimator, Trimmer, ChatHistory, ChatVariables stay in Core
  because they are LLM/storage concerns, not platform concerns.

### Core Interface Design (ST/RisuAI Dual-Platform Review)

> **Full details:** `docs/rewrite/core-interface-design.md`

The key insight: ST and RisuAI differ not in *what* they do, but *where* they
store configuration. ST uses structured fields; RisuAI uses inline decorators.
Core interfaces must define **behavioral contracts**, not unified configuration.

**Interface Changes Summary:**

| Interface | Change | Priority |
|-----------|--------|----------|
| `Macro::Engine::Base` | `#expand(text, environment:)` with Environment protocol | P0 (Wave 2) |
| `Lore::Engine::Base` | `#scan(input)` with ScanInput parameter object | P0 (Wave 2) |
| `ChatVariables::Base` | Add `scope:` parameter (Core: local/global; RisuAI: +temp/function_arg) | P1 (Wave 2) |
| `Prompt::Block` | Relax ROLES/INSERTION_POINTS/BUDGET_GROUPS; add `removable:` flag | P1 (Wave 1) |
| `Prompt::Message` | Reserve optional multimodal/metadata fields; allow passthrough in dialects | P1 (Wave 1) |
| `Trimmer` | Add `strategy:` parameter (:group_order vs :priority) | P2 (Wave 4) |
| `Macro::Registry::Base` | `#register(name, handler, **metadata)` with opaque metadata | P2 (Wave 2) |

### Pipeline Stage Order (SillyTavern Default)

```
SillyTavern.build()  -->  Prompt::Context (mutable build workspace)
                                 |
  1. Hooks (before)     Execute before_build hooks, validate inputs
  2. Lore               Evaluate World Info via SillyTavern::Lore::Engine
  3. Entries            Filter/categorize entries (ST normalization rules)
  4. PinnedGroups       Build 14 ST pinned group slots
  5. Injection          In-chat injections (ST depth/order/role rules)
  6. Compilation        Compile entries -> Block array, expand pinned groups
  7. MacroExpansion     Expand {{macro}} via SillyTavern::Macro::Engine
  8. PlanAssembly       Create Prompt::Plan with blocks, outlets, greeting
  9. Trimming           Enforce token budget via Core Trimmer
                                 |
                           Prompt::Plan
                                 |
              plan.to_messages(dialect)  -->  LLM format (Core Dialect)
```

### Middleware Interface

Each middleware implements `before(context)` and/or `after(context)`:

- `before` -- pre-processing, runs top-down (Hooks first, Trimming last)
- `after` -- post-processing, runs bottom-up (Trimming first, Hooks last)
- Context is mutable; middleware mutates `ctx` directly
- For branching/what-if pipelines, use `ctx.dup` (shallow copy; duplicates key arrays/hashes used by the pipeline)

### Pipeline Customization

```ruby
# Using ST default pipeline
plan = TavernKit::SillyTavern.build do
  character my_char
  user my_user
  preset my_preset
  message "Hello!"
end

# Using generic pipeline with explicit middleware
plan = TavernKit.build(pipeline: my_custom_pipeline) do
  character my_char
  user my_user
  message "Hello!"
end

# Customizing ST pipeline
plan = TavernKit::SillyTavern.build do
  character my_char
  user my_user
  use LoggingMiddleware                        # append custom stage
  insert_before :compilation, MyPreprocessor   # insert at position
  replace :trimming, MyCustomTrimmer           # swap built-in
  message "Hello!"
end
```

## Current State (Wave 4 -- Complete)

Delivered modules:
- **Core (Wave 1):** Character/CharacterCard/PNG, Prompt basics (Pipeline/DSL/Plan/Context/Block/Message), PatternMatcher, PromptEntry (basic), Coerce/Utils/Constants/Errors
- **Core (Wave 2):** interface protocols (Preset/Lore/Macro/Hook/Injection), Lore data (Book/Entry/ScanInput/Result), ChatHistory/ChatVariables, TokenEstimator, Ingest, TrimReport, Prompt::Trace/Instrumenter, PromptEntry enhancements (conditions + pattern matching)
- **SillyTavern (Wave 2):** Preset + Instruct + ContextTemplate (config/data only; middleware chain lands in Wave 4)
- **SillyTavern (Wave 3):** Lore engine (World Info) + Macro engines (V1+V2) + ExamplesParser + ExpanderVars
- **Core (Wave 4):** Trimmer + Dialects (8 formats) + MaxTokensMiddleware guardrails
- **SillyTavern (Wave 4):** 9-stage middleware chain + HookRegistry + InjectionRegistry + GroupContext + ST build()/to_messages convenience

Test status (gem): 593 runs, 0 failures, 0 errors, 0 skips.

## Gap Summary

| Area | Layer | Est. LOC | Status |
|------|-------|----------|--------|
| Preset (60+ fields) + Instruct (24 attrs) + ContextTemplate (Handlebars) | **ST** | ~1,250 | ✅ (Wave 2) |
| ChatHistory + ChatVariables | **Core** | ~400 | ✅ (Wave 2) |
| TokenEstimator | **Core** | ~150 | ✅ (Wave 2) |
| Trimmer | **Core** | ~197 | ✅ (Wave 4) |
| Dialects (8 formats) | **Core** | ~970 | ✅ (Wave 4) |
| Lore Engine + DecoratorParser + TimedEffects + KeyList | **ST** | ~1,750 | ✅ (Wave 3) |
| Lore data (Book + Entry + Result + ScanInput) | **Core** | ~830 | ✅ (Wave 2) |
| Macro (V1+V2 Engine + Registry + Packs + Env + Invocation + Flags + Preprocessors) | **ST** | ~2,500 | ✅ (Wave 3) |
| Macro::Engine::Base + Environment::Base + Registry::Base | **Core** | ~130 | ✅ (Wave 2) |
| Macro handler context (Invocation) | **ST** | ~50 | ✅ (Wave 3) |
| ExamplesParser + ExpanderVars | **ST** | ~260 | ✅ (Wave 3) |
| PromptEntry enhancements | **Core** | ~243 | ✅ (Wave 2 supplement) |
| Middleware (9 stages, incl. extension prompts, author's note, persona positions) | **ST** | ~2,700 | ✅ (Wave 4) |
| HookRegistry + InjectionRegistry (ephemeral, filters) | **ST** | ~300 | ✅ (Wave 4) |
| GroupContext (4 strategies, 3 modes, card merging) | **ST** | ~300 | ✅ (Wave 4) |
| RisuAI (CBS Engine 800-1K + CBS Macros 600-800 + Lore 400-500 + Decorators 250-300 + Templates 200-250 + Regex 250-300 + Triggers 500-700 + Pipeline 190-260) | **RisuAI** | ~3,190-4,110 | Wave 5 |

### Key Behavioral Requirements (from ARCHITECTURE.md)

These must be preserved in the SillyTavern layer:

**Macro System (SillyTavern::Macro):**
- V1 Engine: multi-pass regex expansion (pre-env -> env -> post-env)
- V2 Engine: Chevrotain-equivalent pipeline (lexer -> parser -> CST walker).
  True nesting (`{{outer::{{inner}}}}`), depth-first evaluation, preserves
  unknown macros. Error recovery for malformed macros.
  - Arg splitting must be depth-aware: only top-level `::` separators split
    arguments; nested macros may contain their own `::` (e.g. `{{reverse::{{getvar::x}}}}`).
- **Scoped block macros**: `{{macro}}...{{/macro}}` pairing with auto-trim/dedent.
  Content between tags becomes the last unnamed argument.
- **`{{if}}`/`{{else}}` conditional**: lazy branch resolution, `!` negation,
  auto-resolve bare macro names, variable shorthand conditions, nested
  `{{if}}/{{else}}/{{/if}}` with depth-tracked splitting.
- **Variable shorthand**: `{{.var}}`, `{{$var}}`, 16 operators
  (get/set/inc/dec/add/sub/||/??/||=/??=/==/!=/>/>=/</<= ).
  Lazy value resolution.
- **Macro flags**: 6 types (`!`, `?`, `~`, `>`, `/`, `#`).
  `/` (closing block) and `#` (preserve whitespace) implemented; others parsed
  and ignored.
- **Typed arguments**: `MacroValueType` (string/integer/number/boolean)
  validation with `strictArgs` control.
- **Pre/post-processors**: priority-ordered pipeline hooks for legacy
  normalization and cleanup.
- Case-insensitive matching (`{{char}}` = `{{CHAR}}`)
- Optional `clock:` and `rng:` for deterministic tests
- ~81 macros (with aliases): identity, character, examples, conversation, system,
  instruct mode (19 macros), date/time, random/dice, variables (incl. has/delete),
  utilities, state, conditionals

**Preset / Prompt Manager (SillyTavern::Preset + Middleware::Entries):**
- `prompt_entries` array (ordered Prompt Manager entries)
- Entry normalization: `FORCE_RELATIVE_IDS` (chat_history, chat_examples),
  `FORCE_LAST_IDS` (post_history_instructions)
- In-chat injection: depth 0 = after last, depth N = before Nth-to-last
- Same depth ordering: by `order` asc, then role (Assistant > User > System)
- Same depth+order+role entries merged into single message
- Format templates: `wi_format`, `scenario_format`, `personality_format`
- 14 pinned group slots (main_prompt, persona_description, character_*,
  scenario, chat_examples, chat_history, authors_note, WI positions, etc.)

**Lore Engine (SillyTavern::Lore::Engine):**
- JS regex support via `js_regex_to_ruby` gem
- Group scoring: `groupOverride`, `groupWeight`, weighted random
- Min activations: increase scan depth until N entries activate
- Forced activations: external override
- `ignoreBudget` entries bypass token budget cutoff
- Timed effects: sticky/cooldown/delay state tracking
- **Non-chat scan data opt-in**: 6 `match*` boolean flags per entry
  (`matchPersonaDescription`, `matchCharacterDescription`,
  `matchCharacterPersonality`, `matchCharacterDepthPrompt`,
  `matchScenario`, `matchCreatorNotes`) allow entries to match
  against non-chat data sources
- **Generation type triggers**: `triggers[]` filters entries by generation type
  (normal, continue, impersonate, swipe, quiet)
- **Character filtering**: `characterFilter.names[]`, `.tags[]`, `.isExclude`
  filter entries by character identity
- **Probability toggle**: `useProbability` enables/disables probability check

**Trimmer (Core -- TavernKit::Trimmer):**
- Disables blocks in-place (`enabled: false`), does not remove
- Pluggable strategy via `strategy:` parameter:
  - `:group_order` (ST default): `:system` (never evicted) > `:examples` >
    `:lore` > `:history`. Examples evicted as whole dialogues. History
    oldest-first, preserving latest user message.
  - `:priority` (RisuAI): sort by `block.priority`, evict lowest first.
    `@ignore_on_max_context` sets priority -1000. Respects `removable` flag.
- Returns detailed `trim_report`

**HookRegistry (SillyTavern::HookRegistry):**
- `before_build`: mutable = character, user, history, user_message
- `after_build`: mutable = plan (blocks manipulation)
- Hooks receive `Prompt::Context` directly (no separate HookContext type)

**InjectionRegistry (SillyTavern::InjectionRegistry):**
- Mirrors STscript `/inject` feature
- Overlapping ID = replace (idempotent)
- Positions: `:before` (BEFORE_PROMPT), `:after` (IN_PROMPT), `:chat` (IN_CHAT),
  `:none` (NONE -- WI scanning only)
- Flags: `scan` (include in WI scanning), `ephemeral` (one-shot, removed after
  generation), `filter` (optional closure returning boolean)

**Context Template (SillyTavern::ContextTemplate):**
- Handlebars-based `story_string` with conditional placeholders:
  `system`, `description`, `personality`, `scenario`, `persona`, `char`, `user`,
  `wiBefore`, `wiAfter` (`loreBefore`/`loreAfter` aliases),
  `anchorBefore`, `anchorAfter`, `mesExamples`, `mesExamplesRaw`
- `chat_start` and `example_separator` markers (default: `"***"`)
- Position config: `story_string_position` (IN_PROMPT or IN_CHAT),
  `story_string_depth`, `story_string_role`
- `use_stop_strings` flag adds markers to stopping strings
- **Important:** `story_string` commonly contains ST macros (e.g. `{{trim}}`).
  Wave 2 ContextTemplate renders Handlebars blocks + known placeholders only;
  unknown `{{...}}` tokens are preserved for Wave 3 Macro expansion.

**Extension Prompt Injection (SillyTavern::Middleware::Injection):**
- `extension_prompt_types`: NONE (-1), IN_PROMPT (0), IN_CHAT (1),
  BEFORE_PROMPT (2)
- `extension_prompt_roles`: SYSTEM (0), USER (1), ASSISTANT (2)
- Built-in IDs: `1_memory`, `2_floating_prompt`, `3_vectors`,
  `4_vectors_data_bank`, `PERSONA_DESCRIPTION`, `DEPTH_PROMPT`
- Author's Note: interval-based insertion (`note_interval`), character-specific
  overrides (replace/before/after)
- Vector/Data Bank content is provided externally (hooks/injections), not fetched
  by TavernKit.

**Persona Description (SillyTavern::Middleware::Injection):**
- 5 positions: IN_PROMPT (0), AFTER_CHAR (1, deprecated), TOP_AN (2),
  BOTTOM_AN (3), AT_DEPTH (4), NONE (9)
- `depth` (default 2) and `role` (default SYSTEM) for AT_DEPTH injection
- Lock system: chat > character > default (priority ascending)

**Stopping Strings (SillyTavern::Preset):**
- 4 sources assembled in order: (1) names-based, (2) instruct sequences,
  (3) context start markers, (4) custom strings
- Names: `"\n{name}:"` for character, user, group members
- Instruct: all sequences if `sequences_as_stop_strings` enabled
- Context: `chat_start` and `example_separator` if `use_stop_strings`
- Custom: JSON array + ephemeral runtime array, **macro-substituted** (requires a macro expander)
- Single-line mode prepends `"\n"` to all stops

**Group Chat (SillyTavern::GroupContext):**
- 4 activation strategies: NATURAL (0), LIST (1), MANUAL (2), POOLED (3)
- 3 generation modes: SWAP (0), APPEND (1), APPEND_DISABLED (2)
- Card merging in APPEND modes: join prefix/suffix with `<FIELDNAME>` placeholders
- Group nudge: `"[Write the next reply only as {{char}}.]"` (default)
- `allow_self_responses`, `disabled_members`, `auto_mode_delay`

**Continue / Impersonate Mode (SillyTavern::Middleware::PlanAssembly):**
- Continue: `continue_nudge_prompt`, `continue_prefill`, `continue_postfix`
  (NONE/SPACE/NEWLINE/DOUBLE_NEWLINE)
- Impersonate: `impersonation_prompt`, `assistant_impersonation` (Claude-specific)
- Assistant prefill: `assistant_prefill` (normal), `assistant_impersonation`
  (impersonate). Only for Claude source.

**Block attributes (Core -- Prompt::Block):**
- `id`, `role`, `content`, `name`, `slot`, `enabled`
- `insertion_point`, `depth`, `order`, `priority`, `token_budget_group`
- `tags`, `metadata`
- Implemented in Core (Wave 1): `role`/`insertion_point`/`token_budget_group`
  are type-checked as `Symbol` (no fixed whitelist; supports `:tool`/`:function`); `removable:` is supported.

**Message attributes (Core -- Prompt::Message):**
- `role`, `content`, `name` plus optional `attachments` and `metadata`
  passthrough for future provider/tooling needs (tool calls / tool results).
  Core allows `:tool` / `:function` roles (ST ignores; Dialects handle conversion).

**Plan (Core -- Prompt::Plan):**
- `blocks` (all, including disabled) / `enabled_blocks` (active only)
- `greeting` / `greeting_index`, `warnings`, `trim_report`, `outlets`
- Optional observability payload: `trace` (`Prompt::Trace`) (stage timings,
  token counts, eviction reasons, and a stable prompt fingerprint for caching)
  populated only when debug instrumentation is enabled (production default: off).

## Wave Plan

### Wave 2 -- Configuration & Data Layer

**Core interfaces + Core data structures + SillyTavern config.**

#### 2a. Core Interfaces

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `Preset::Base` | Core | Minimal preset interface (context_window_tokens, reserved_response_tokens) | 40-60 |
| `Lore::Engine::Base` | Core | Interface: `#scan(input)` -> Lore::Result | 30-40 |
| `Macro::Engine::Base` + `Macro::Environment::Base` | Core | Interface: `#expand(text, environment:)` -> String; Environment protocol provides character_name, user_name, get_var/set_var(scope:); subclassed by ST/RisuAI | 60-80 |
| `Macro::Registry::Base` | Core | Interface: `#register(name, handler, **metadata)`, `#get`, `#has?`; metadata opaque to Core | 30-40 |
| `HookRegistry::Base` | Core | Interface: `#before_build(&block)`, `#after_build(&block)`, `#run_before_build(ctx)`, `#run_after_build(ctx)` | 40-60 |
| `InjectionRegistry::Base` | Core | Interface: `#register(id:, content:, position:, **opts)`, `#remove(id:)`, `#each`, `#ephemeral_ids` | 40-60 |

#### 2b. Core Data Structures (Lore)

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `Lore::ScanInput` | Core | Parameter object: messages, books, budget; subclassed by ST/RisuAI for platform-specific fields | 80-100 |
| `Lore::Book` | Core | Book data structure (character_book or standalone) | 150-200 |
| `Lore::Entry` | Core | Entry with minimal shared schema + `extensions` Hash (ST/RisuAI-specific fields live in extensions; treat keys as string-keyed at serialization boundaries; Core may accept string/symbol keys) | 250-350 |
| `Lore::Result` | Core | Activation results with token costs and TrimReport | 150-200 |

#### 2c. Core Implementations

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `ChatHistory::Base` + `InMemory` | Core | Abstract protocol + default impl | 150-200 |
| `ChatVariables::Base` + `InMemory` | Core | Type-safe variable storage + default impl; `scope:` parameter (Core: `:local`/`:global`; RisuAI extends with `:temp`/`:function_arg`) | 150-200 |
| `TokenEstimator` | Core | Token counting (tiktoken_ruby), optional `model_hint:`, **pluggable adapter interface** | 100-150 |
| `Ingest` | Core | File-based ingestion returning `Ingest::Bundle` (character + main image + lazy assets + warnings). Core parsing stays Hash-only. | 80-120 |
| `TrimReport` + `TrimResult` | Core | Shared budgeting result value objects (Lore budget trimming + Trimmer); include eviction reasons + provenance for debugging | 60-100 |
| `Prompt::Trace` + `Prompt::Instrumenter` | Core | Optional pipeline instrumentation (stage timings + key counters + fingerprint); opt-in via `context.instrumenter` (nil by default); integrates with `Context#warnings`; no ActiveSupport dependency | 100-150 |

#### 2d. SillyTavern Config

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `SillyTavern::Preset` | ST | 60+ ST config keys (sampling, budget, prompts, templates, nudges, prefill, postfix), ST preset JSON import, `with()`, `#stopping_strings(context)` assembling 4 sources | 400-500 |
| `SillyTavern::Instruct` | ST | Text completion formatting, 24+ attributes, stop sequence assembly, names behavior (NONE/FORCE/ALWAYS). Macro substitution is supported via an injected expander (Wave 3+) | 300-400 |
| `SillyTavern::ContextTemplate` | ST | Handlebars-based story_string with placeholders. Does **not** evaluate ST macros (e.g. `{{trim}}`) in Wave 2; unknown `{{...}}` tokens are preserved for Wave 3 Macro expansion | 200-250 |
**Tests:**
- Core interface compliance tests
- Lore data structure tests (Book, Entry, Result, ScanInput)
- ST preset import round-trip tests (all 60+ fields)
- ChatHistory protocol + message contract + InMemory tests
- TokenEstimator accuracy tests
- Pipeline tracing/instrumentation tests (Trace collector + stage timing + warnings integration)
- ContextTemplate story_string Handlebars compilation tests
- Instruct stop sequence assembly tests
- Preset stopping strings integration tests
- Ingest behavior tests (JSON/PNG/APNG/BYAF/CHARX), incl. tmp lifecycle + lazy assets

**Deliverable:** Core interfaces defined. Lore data structures ready for engine
implementations. ST Preset loadable from JSON with all prompt-affecting fields.
ContextTemplate renders Handlebars blocks and preserves ST macros for Wave 3.
ChatHistory::Base subclassable by Rails. TokenEstimator callable standalone.
Stopping strings assembled from 4 sources (macro substitution via injected expander).

### Wave 3 -- Content Expansion Layer

**SillyTavern engine implementations.**

Scope updated after ST v1.15.0 source alignment
(see `docs/rewrite/st-alignment-delta-v1.15.0.md` -- `resources/SillyTavern` on `staging` @ `bba43f33219e41de7331b61f6872f5c7227503a3`).

#### 3a. Lore / World Info Engine

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `SillyTavern::Lore::WorldInfoImporter` | ST | Import/normalize ST native World Info JSON -> Core `Lore::Book`/`Lore::Entry`; canonicalize extension keys to snake_case for internal consistency. | 120-200 |
| `SillyTavern::Lore::Engine` | ST | Implements `Lore::Engine::Base`: keyword matching, recursive scanning, timed effects, min activations, group scoring, JS regex, non-chat scan data opt-in, generation trigger filtering, character filtering. **Callback interfaces:** `force_activate` (external forced activation, maps to `WORLDINFO_FORCE_ACTIVATE` event), `on_scan_done` (per-loop-iteration hook, maps to `WORLDINFO_SCAN_DONE` event). | 500-700 |
| `SillyTavern::Lore::ScanInput` | ST | Extends Core `Lore::ScanInput` with ST-specific fields for non-chat scan context/injects, generation trigger, timed state, character identity (name/tags), forced/min activations, and turn count. | 80-120 |
| `SillyTavern::Lore::DecoratorParser` | ST | ST decorator syntax (`@@activate`, `@@dont_activate`) | 200-250 |
| `SillyTavern::Lore::TimedEffects` | ST | sticky/cooldown/delay state tracking | 200-250 |
| `SillyTavern::Lore::KeyList` | ST | Comma-separated keyword parsing | 80-100 |

**Compatibility notes (ST staging reality):**
- `Lore::Entry#extensions` key shapes are inconsistent across ST formats. The engine must accept both snake_case and camelCase for the same semantics. Examples:
  - `extensions.selectiveLogic` (Character Book export) vs `selectiveLogic` (ST native World Info)
  - `extensions.useProbability` vs `useProbability`
  - `extensions.match_persona_description` (Character Book export) vs `matchPersonaDescription` (ST native World Info)
- `SillyTavern::Lore::WorldInfoImporter` normalizes these into a canonical snake_case representation; the engine still treats unknown/missing fields as defaults (tolerant external input).
- `SillyTavern::Lore::WorldInfoImporter` also normalizes numeric entry `position` codes into canonical strings: `before_char_defs`, `after_char_defs`, `top_of_an`, `bottom_of_an`, `at_depth`, `before_example_messages`, `after_example_messages`, `outlet`.

#### 3b. Macro System

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `SillyTavern::Macro::V1Engine` | ST | Multi-pass regex expansion (legacy) | 200-250 |
| `SillyTavern::Macro::V2Engine` | ST | Chevrotain-equivalent pipeline: lexer (multi-mode) + parser (CST) + walker. Scoped block macros (`{{macro}}...{{/macro}}`), variable shorthand (16 operators), macro flags (6 types, 2 implemented), lazy branch resolution, auto-trim/dedent, error recovery | 500-700 |
| `SillyTavern::Macro::Registry` | ST | Implements `Macro::Registry::Base`, typed args (`MacroValueType`), arg validation, `strictArgs`, `delayArgResolution`, `list` support | 200-250 |
| `SillyTavern::Macro::Packs` | ST | ~81 built-in ST macros (utility, random, names, character, chat, time, variable, prompts, state), including `{{if}}`/`{{else}}`, `{{space}}`, `{{hasvar}}`/`{{deletevar}}`, `{{hasglobalvar}}`/`{{deleteglobalvar}}`, `{{groupNotMuted}}`, `{{hasExtension}}` | 400-500 |
| `SillyTavern::Macro::Environment` | ST | Extensible macro execution context, lazy providers | 100-150 |
| `SillyTavern::Macro::Invocation` | ST | Call-site object (`MacroCall`): name, args, flags, isScoped, rawInner, rawArgs, range, globalOffset | 80-100 |
| `SillyTavern::Macro::Flags` | ST | 6 flag types: `!` (immediate), `?` (delayed), `~` (re-evaluate), `>` (filter), `/` (closing block), `#` (preserve whitespace). Implement `/` and `#`; parse and ignore others | 60-80 |
| `SillyTavern::Macro::Preprocessors` | ST | Priority-ordered pre/post-processors: legacy angle-bracket normalization, `{{time_UTC+N}}` normalization, brace unescaping, `{{trim}}` cleanup, `ELSE_MARKER` cleanup | 80-100 |

**Error handling policy (Wave 3):**
- **Tolerant for external/user input by default:** malformed macros, unknown macros, and invalid args should not hard-fail prompt building. Prefer: preserve raw `{{...}}` tokens, return best-effort output, and record diagnostics (warnings) when possible.
- **Fail-fast for programmer errors:** unexpected exceptions (bugs in TavernKit or custom handlers) must bubble up (do not swallow).
- Add a **strict mode** (opt-in) to turn diagnostics into exceptions (e.g. `StrictModeError`/`MacroError`) for tests and debugging.

#### 3c. Other

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `SillyTavern::ExamplesParser` | ST | `<START>` marker parsing | 150-200 |
| `SillyTavern::ExpanderVars` | ST | Context -> macro vars mapping | 60-80 |

Note: PromptEntry conditions + pattern matching moved to Wave 2 supplement.

**Tests:**
- Tests are derived from ST/RisuAI behavior, but **must be re-authored** (no direct copying of upstream fixtures/tests due to license incompatibility).
- Lore: keyword matching, recursive scanning, budget, timed effects, decorators,
  non-chat scan data, generation triggers, character filtering
- Macro: all ~81 ST macros, scoped blocks (`{{if}}...{{else}}...{{/if}}`),
  variable shorthand (16 operators), flags, typed arg validation, legacy markers
- ✅ Unlocked ST World Info characterization tests
- ✅ Unlocked ST Macros characterization tests
- ✅ Unlocked RisuAI Lorebook characterization tests (Wave 5)

**Deliverable:** `SillyTavern::Lore::Engine` activates world info independently
with full entry field support (40+ fields). `SillyTavern::Macro::V2Engine`
expands all ~81 ST macros including conditionals and variable shorthand.
Both usable standalone by Rails and as middleware dependencies.

### Wave 4 -- Orchestration & Output Layer

**Core output infra + SillyTavern middleware chain + full build() entry.**

Contracts pinned for implementation alignment:
- `docs/rewrite/wave4-contracts.md` (Dialects tool/function passthrough, Trimmer bundled eviction, strict/debug conventions)

Dialect-aware ST behavior:
- `ctx.dialect == :text` uses ContextTemplate (story string) + anchors for text-completion style prompts
- otherwise uses chat-style prompt assembly (PromptManager-like)

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `Trimmer` | Core | Pluggable eviction strategy: `:group_order` (ST: examples -> lore -> history) or `:priority` (RisuAI: sort by priority, evict lowest first) | 180-230 |
| `Dialects::Base` | Core | Dialect interface + passthrough contract for tool calls/results (via Message metadata) | 40-60 |
| `Dialects::OpenAI` | Core | ChatCompletions `[{role, content, name?}]` + tool calls/tool results passthrough; squash_system option | 80-100 |
| `Dialects::Anthropic` | Core | `{messages, system}`, content blocks (incl. tool use / tool result) | 120-150 |
| `Dialects::Google` | Core | `{contents, system_instruction}` | 80-100 |
| `Dialects::Cohere` | Core | `{chat_history}` | 60-80 |
| `Dialects::AI21` | Core | `[{role, content}]` | 60-80 |
| `Dialects::Mistral` | Core | `[{role, content}]` | 60-80 |
| `Dialects::XAI` | Core | `[{role, content}]` | 60-80 |
| `Dialects::Text` | Core | `{prompt, stop_sequences}`, instruct formatting | 80-100 |
| `SillyTavern::Middleware::Hooks` | ST | Before/after build hook execution | 80-100 |
| `SillyTavern::Middleware::Lore` | ST | World info activation + plan injection | 300-400 |
| `SillyTavern::Middleware::Entries` | ST | Entry normalization (FORCE_RELATIVE, FORCE_LAST) | 150-200 |
| `SillyTavern::Middleware::PinnedGroups` | ST | 14 pinned group slots | 300-400 |
| `SillyTavern::Middleware::Injection` | ST | In-chat depth/order/role rules, extension prompt injection (extension_prompt_types: NONE/-1, IN_PROMPT/0, IN_CHAT/1, BEFORE_PROMPT/2), author's note interval logic, persona description positions (IN_PROMPT/TOP_AN/BOTTOM_AN/AT_DEPTH/NONE), ContextTemplate story_string injection (position/depth/role) | 500-600 |
| `SillyTavern::Middleware::Compilation` | ST | Block compilation from entries | 250-350 |
| `SillyTavern::Middleware::MacroExpansion` | ST | Macro expansion phase | 40-60 |
| `SillyTavern::Middleware::PlanAssembly` | ST | Final plan construction, continue/impersonate mode handling (nudge prompts, prefill, postfix types), Claude-specific assistant_impersonation | 100-150 |
| `SillyTavern::Middleware::Trimming` | ST | Token budget enforcement (delegates to Core Trimmer) | 50-80 |
| `SillyTavern::HookRegistry` | ST | Before/after hooks (hooks receive Prompt::Context) | 120-160 |
| `SillyTavern::InjectionRegistry` | ST | `/inject` parity (position mapping: before/after/chat/none), idempotent, scan/ephemeral flags, optional filter closures | 120-150 |
| `SillyTavern::GroupContext` | ST | Multi-character context: 4 activation strategies (NATURAL/LIST/MANUAL/POOLED), 3 generation modes (SWAP/APPEND/APPEND_DISABLED), **Decision sync** (app scheduling vs TavernKit), card merging (join prefix/suffix with `<FIELDNAME>` placeholders), disabled_members, group nudge | 250-300 |
| `SillyTavern::Pipeline` | ST | Default 9-stage middleware chain | 60-80 |
| `TavernKit::SillyTavern.build()` | ST | Convenience entry with ST defaults | 60-80 |
| `TavernKit.build()` | Core | Generic entry requiring explicit pipeline | 40-60 |

**Tests:**
- End-to-end: character + preset + lore + history -> plan -> messages
- All 8 dialect output format tests
- Dialects: tool calls/tool results passthrough + conversion tests (OpenAI/Anthropic)
- Middleware ordering and insertion tests
- Trimmer eviction strategy tests
- Trimmer failure mode: mandatory prompts exceed budget => `MaxTokensExceededError` (`stage: :trimming`)
- Injection tests: extension prompt types, persona positions, author's note interval, story_string position/depth/role (and instruct prefix/suffix wrapping), **doChatInject parity** (depth semantics + continue depth-0 shift + role ordering)
- Group context: activation strategies, generation modes, card merging
- Continue/impersonate: nudge prompts, prefill, postfix types
- InjectionRegistry: ephemeral flag, position mapping, filter closures
- ✅ Unlocked ST Prompt Manager characterization tests
- ✅ Unlocked ST Character Cards characterization tests

**Deliverable:** `TavernKit::SillyTavern.build()` runs end-to-end.
`plan.to_messages(dialect)` works for all 8 formats. Full ST middleware
chain operational. Extension prompt injection, author's note, persona description,
continue/impersonate modes, and group chat behaviors all functional.

#### Implementation Notes / Risk Control (Wave 4)

Stage 5 (`SillyTavern::Middleware::Injection`) is intentionally the most complex.
To keep the implementation readable and testable, split it into internal helpers
(or sub-objects) with narrow responsibilities:

- `Injection::RegistryNormalizer` (coercion + aliasing + stable ordering + filter evaluation)
- `Injection::PersonaDescription` (5 persona positions)
- `Injection::AuthorsNote` (interval logic + positions)
- `Injection::StoryString` (text-dialect-only assembly + in-chat injection)
- `Injection::ChatInserter` (depth/role ordering + merge rules)

`SillyTavern::GroupContext` behaviors (pulled from ST staging `group-chats.js`):

- Activation strategy NATURAL:
  - If user typed input, parse mentions and activate mentioned members (excluding last speaker unless allow_self_responses).
  - Then roll talkativeness for each member (shuffled), may activate multiple members.
  - If none activated, pick one random member (prefer talkativeness > 0 members).
- LIST: activate all enabled members in list order.
- POOLED: pick exactly one member who has not spoken since the last user message; otherwise pick random excluding the last speaker when possible.
- MANUAL: if NOT user-triggered input, pick one random enabled member; user-triggered input yields no activation (user message just sends).

Special generation types override activation strategy:
- `quiet`: 1 member chosen from swipe logic (allowSystem), fallback to first member.
- `swipe` / `continue`: members chosen from swipe logic (last speaker), error if deleted.
- `impersonate`: pick 1 random member.

### Wave 5 -- RisuAI Implementation + Parity Gate

Scope updated after RisuAI source scan
(see `docs/rewrite/risuai-alignment-delta.md`).

Because ST and RisuAI semantics differ, Wave 5 prefers **independent platform
implementations** over shared “almost-the-same” helpers. Redundancy is OK; avoid
introducing hacks or cross-coupling to keep both sides passing.

**Recommended execution order (to reduce drift):**
1. 5b → 5c → 5d (CBS Engine → Lorebook → Template Cards) -- core functionality
2. 5e → 5f (Regex Scripts → Triggers) -- extensions
3. 5g (Memory interface) -- contract only
4. 5h (Parity Verification) -- final gate

#### 5a. Wave 5 Kickoff (Test Harness + Guardrails)

This sub-wave is intentionally small: it provides the scaffolding that keeps
Wave 5 from drifting while implementing RisuAI.

##### Wave 5a Execution Plan (Test Taxonomy + Guardrails)

**Test taxonomy (to avoid “跑偏”):**

- **Conformance tests** (normative): prove we implement *a written spec* correctly.
  - Example: CCv2/CCv3 parsing/export invariants, BYAF/CHARX safety limits, known enum/value coercions.
  - Location suggestion: `lib/tavern_kit/test/conformance/`.
- **Characterization tests** (descriptive): lock down behavior observed in ST/RisuAI, without copying their fixtures/tests.
  - Location: `lib/tavern_kit/test/characterization/` (already in use).
  - Each contract test must state which upstream function(s) it was derived from (file + function name).
- **Integration tests** (end-to-end): exercise “real” pipelines from build inputs to provider messages (dialects),
  including trimming and warnings/trace surfaces.
  - Location suggestion: `lib/tavern_kit/test/integration/`.

**Regression guardrails (run continuously during Wave 5):**

- `cd lib/tavern_kit && bundle exec rake test:guardrails`
  - Runs Wave 4 contract tests + ST characterization tests (fast subset).
  - Must stay green before each Wave 5 commit.
- `cd lib/tavern_kit && bundle exec rake test:conformance`
- `cd lib/tavern_kit && bundle exec rake test:integration`
- `cd lib/tavern_kit && bundle exec rake test:risuai`
- `cd lib/tavern_kit && bundle exec rake test:wave5` (meta task)

**RisuAI runtime contract (to avoid hidden coupling):**
- RisuAI-specific runtime state should be passed via `ctx.runtime` (a Runtime
  object), never by modifying Core internals.
- The pipeline builds the runtime once at Stage 1 from app-provided runtime
  input (`ctx[:runtime]` or `DSL#runtime({ ... })`) and then treats it as
  immutable for the rest of the pipeline (must not be replaced by middleware).
- Canonical form for runtime input: **snake_case symbol keys**
  (e.g. `chat_index:`). The runtime normalizes string/camelCase keys once at
  Stage 1 so later stages can rely on the canonical form.
- Recommended shape (all optional unless stated):
  - `chat_index` (Integer) -- current message index in the chat
    (RisuAI `matcherArg.chatID` / `chat.chatIndex`). `-1` means “no message
    context” (common during prompt building).
  - `message_index` (Integer) -- current chat length (message count). Used as
    the deterministic RNG `cid` seed for `pick`/`rollp`.
  - `rng_word` (String) -- deterministic RNG seed word. Upstream uses
    `chaId + chat.id`; TavernKit cannot infer those IDs, so applications should
    pass a stable string when exact parity matters.
  - `cbs_conditions` (Hash) -- optional CBS “matcherArg” flags that affect a
    small subset of macros (e.g. `role`, `isfirstmsg`). Keys are normalized once
    at runtime build (snake_case symbols in input; stored as normalized strings).
  - `toggles` (Hash) -- toggle name → string value (RisuAI truthiness rules apply).
  - `metadata` (Hash) -- free-form (RisuAI exposes 15+ metadata macros).
  - `modules` (Array) -- enabled modules list (for module_* macros).
  - `assets` (Hash/Array) -- app-provided asset manifest (for media macros).
- The generic DSL supports this via `runtime({ ... })` or `meta(:runtime, { ... })`.

**Defaulting policy (TavernKit-only):**
- Upstream RisuAI runs inside an app that always provides chat/message state.
  TavernKit may be used in smaller scripts/tests, so missing runtime keys are
  treated as an **app integration gap**.
- In tolerant mode, missing keys default to safe values:
  - `chat_index`: `-1`
  - `message_index`: derived from history size when available; otherwise `0`
  - `rng_word`: `character.name` when available; otherwise `"0"`
  - `cbs_conditions`: `{}`
  - `toggles`: `{}`; `metadata`: `{}`; `modules`: `[]`; `assets`: `{}`/`[]`
- In strict/debug mode, missing runtime keys may raise to make integration bugs
  obvious during tests.

**I/O boundary policy (Wave 5):**
- TavernKit remains prompt-building focused; anything requiring file/network/UI
  access must be provided via environment hooks/data from the application layer.
- CBS macros / triggers that depend on app-owned I/O should:
  - Return `""` / no-op in tolerant mode when capability is missing.
  - Raise in strict/debug mode (or emit a warning that strict mode escalates).

**Anti-drift checklist (run after each Wave 5 step / commit):**
- Does this follow `docs/rewrite/risuai-alignment-delta.md`?
- Did we cite the correct upstream RisuAI source location (file + function and/or line range) in code comments/tests?
- Did we reuse Core interfaces (`Macro::Engine::Base`, `Lore::Engine::Base`, Pipeline/Context/Trimmer)?
- Is code style consistent with the ST layer (small files, clear naming, tolerant input handling, strict mode for tests/debug)?
- Did we unskip and pass the relevant pending characterization tests for this step?
- Did we avoid ST-specific concepts leaking into `TavernKit::RisuAI` (and vice versa)?

#### 5b. RisuAI CBS Macro Engine

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `RisuAI::CBS::Engine` | RisuAI | Implements `Macro::Engine::Base` via `#expand(text, environment:)` but uses CBS-specific semantics. CBS parser: 10 block types (#when/#if/#each/#func/#escape/#puredisplay/#pure/#code/#if_pure/:else), 13+ #when operators (is/isnot, >/>=/</<= , and/or/not, var/toggle, vis/tis), stack-based evaluation, 10 processing modes, 20-depth call stack limit, #func/call function system, §-delimited arrays, deterministic RNG (message-index seed) | 800-1,000 |
| `RisuAI::CBS::Macros` | RisuAI | **Prompt-building scope.** Implement the macros required for message/prompt assembly (character/user/history/vars/math/strings/collections/unicode/crypto/misc) and app-state macros sourced from `runtime.metadata` (e.g. `mainprompt`, `jb`, `maxcontext`, `jbtoggled`). UI/DB-dependent macros (assets/media buttons, DB fetches, downloads, etc.) are deferred and should be provided by the application layer / adapters if needed. | 600-800 |
| `RisuAI::CBS::Environment` | RisuAI | Implements `Macro::Environment::Base` for CBS evaluation. Manages variable scopes (`:local/:global` + RisuAI-only `:temp/:function_arg`) without changing Core behavior. Integrates with Core `ChatVariables` for persisted scopes and uses in-memory storage for ephemeral scopes. | 120-180 |

#### 5c. RisuAI Lorebook

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `RisuAI::Lore::ScanInput` | RisuAI | Subclass/parameter object for `Lore::Engine::Base#scan`, carrying RisuAI-specific scan config (depth, recursion flags, decorator-driven injection ops, etc.) while keeping Core contract stable. | 80-120 |
| `RisuAI::Lore::Engine` | RisuAI | Iterative activation loop with recursive scanning, keyword matching (full-word/partial/regex), selective AND logic, token budget with priority sorting, injection graph (4 ops: append/prepend/replace/inject_at), lore sources (character + chat + module), `@ignore_on_max_context` (priority -1000), `@keep/@dont_activate_after_match` via chat vars | 400-500 |
| `RisuAI::Lore::DecoratorParser` | RisuAI | 30+ decorators parsed via CCardLib.decorator.parse(): @depth/@reverse_depth, @role, @position (pt_*,after_desc,before_desc,personality,scenario), @scan_depth, @priority, @activate/@dont_activate, @activate_only_after/@activate_only_every, @is_greeting, @probability, @additional_keys/@exclude_keys/@exclude_keys_all, @match_full_word/@match_partial_word, @recursive/@unrecursive/@no_recursive_search, @inject_lore/@inject_at/@inject_replace/@inject_prepend, @ignore_on_max_context, @disable_ui_prompt | 250-300 |

#### 5d. RisuAI Prompt Assembly

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `RisuAI::TemplateCards` | RisuAI | 6 prompt item types (Plain, Typed, Chat, AuthorNote, ChatML, Cache), {{position::name}} template injection, innerFormat wrapping via {{slot}}, ST preset import conversion (stChatConvert), postEverything auto-append, utilityBot bypass | 200-250 |

#### 5e. RisuAI Scripting

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `RisuAI::RegexScripts` | RisuAI | 6 execution types (modify input/output/request/display, edit translation, disabled), flag system (<order N>, <cbs>, <inject>, <move_top/bottom>, <repeat_back>, <no_end_nl>), @@ directives (emo, inject, move_top/bottom, repeat_back), script ordering. Note: compiled regex + processScript-style output are cached via the Core LRU helper (Wave 6). | 250-300 |
| `RisuAI::Triggers` | RisuAI | v1 + v2 trigger runner with lowLevelAccess gating and recursion limits. Wave 5 focuses on prompt-building safe effects (control flow + vars + string/array/dict + chat ops + tokenize + replace). UI/DB effects (alerts/LLM/imggen/lorebook persistence) are app-owned and may be added later via adapters (Wave 6+). | 500-700 |

#### 5f. RisuAI Pipeline

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `RisuAI::Pipeline` | RisuAI | 4-stage processing (Prompt Preparation → Memory Integration → Final Formatting → API Request), message processing flow (input → CBS → regex → triggers → display) | 150-200 |
| `RisuAI::RisuAI.build()` | RisuAI | Convenience entry with RisuAI defaults | 40-60 |

#### 5g. RisuAI Memory (Interface Only)

| Module | Layer | Description | Est. LOC |
|--------|-------|-------------|----------|
| `RisuAI::Memory::Base` | RisuAI | **Interface-only** for HypaMemory/SupaMemory integration. Defines hooks for pipeline Stage 2 (Memory Integration) without implementing actual retrieval/compression. Application layer provides concrete adapter. | 80-120 |
| `RisuAI::Memory::MemoryInput` | RisuAI | Parameter object for memory stage: `summaries`, `pinned_memories`, `metadata`, `budget_tokens` | 60-80 |
| `RisuAI::Memory::MemoryResult` | RisuAI | Result object: `blocks` (memory-derived Blocks), `tokens_used`, `compression_type` | 60-80 |

**Memory Interface Contract:**

```ruby
module TavernKit::RisuAI::Memory
  class Base
    # @param input [MemoryInput] memory artifacts from application layer
    # @param context [Prompt::Context] pipeline context
    # @return [MemoryResult] blocks to inject + metadata
    def integrate(input, context:) = raise NotImplementedError
  end

  # Application layer implements actual retrieval:
  # class MyMemoryAdapter < TavernKit::RisuAI::Memory::Base
  #   def integrate(input, context:)
  #     # Fetch from vector DB, apply compression, etc.
  #     MemoryResult.new(blocks: [...], tokens_used: 500, compression_type: :hypa_v3)
  #   end
  # end
end
```

**Rationale:** Memory retrieval involves vector matching, external DB calls, and
compression algorithms that belong in the application layer. TavernKit provides:
- Interface contract for pipeline integration
- Block injection hooks at Stage 2
- Budget participation (memory blocks have `token_budget_group: :memory`)
- `removable:` and `priority:` support for trimming decisions

Actual HypaMemory/SupaMemory implementation is deferred until test samples are
available.

**Tests:**
- CBS: all 10 block types, 13+ #when operators, 130+ macros, variable scopes,
  math expressions, deterministic RNG, function definitions, processing modes
- Lorebook: keyword matching (3 modes), recursive scanning, budget/priority,
  30+ decorators, injection graph (4 operations), timed activation gates
- Template cards: 6 item types, position injection, innerFormat, ST import
- Regex scripts: 6 execution types, flag parsing, @@ directives, ordering
- Triggers: v1 effects, v2 control flow, v2 safe effects (vars/string/array/dict/chat ops/tokenize/replace),
  lowLevelAccess gating, recursion limits
- Memory: interface compliance tests (mock adapter), block injection, budget participation
- End-to-end: character + RisuAI template + lore + CBS macros -> plan -> messages

#### 5h. Parity Verification (Final Gate)

This is the Wave 5 “stop the line” gate. Run it only after 5b-5g are landed.

| Task | Layer | Description |
|------|-------|-------------|
| ✅ Unlock characterization tests | RisuAI | RisuAI (15) |
| Recreate ST compatibility test suite | ST | 8 areas worth of coverage (behavior-derived, not copied) |
| Spec conformance tests | Core | CCv2 + CCv3 spec conformance and TavernKit-defined intentional divergences |
| Integration verification | All | Ensure downstream Rails app can work with both ST and RisuAI pipelines |

**Concrete worklist (Wave 5h):**

- ✅ **RisuAI characterization tests**: all green (0 skips).
  (Originally tracked as 15 pending tests; now fully landed.)
  - `lib/tavern_kit/test/characterization/risuai_cbs_test.rb` (5)
  - `lib/tavern_kit/test/characterization/risuai_lorebook_test.rb` (4)
  - `lib/tavern_kit/test/characterization/risuai_regex_scripts_test.rb` (3)
  - `lib/tavern_kit/test/characterization/risuai_triggers_test.rb` (3)
- **ST compatibility suite (8 areas)** (behavior-derived, not copied):
  - Entry normalization + prompt entries ordering/enable rules
  - In-chat injection ordering (depth / reverse-depth / role effects)
  - Macro v1/v2 deltas + variables (locals/global) + unknown macro tolerance
  - Preset loading + computed stopping strings behavior
  - Prompt assembly order (default + custom relative entries) + PHI positioning
  - Scan buffer / lore scan inputs (messages + injects + outlets)
  - Utility prompts (continue / impersonate / group nudge) + displacement rules
  - World Info positions mapping + timed effects + forced activation hooks
- **Conformance tests (Core)**:
  - `lib/tavern_kit/test/conformance/ccv2_conformance_test.rb`
  - `lib/tavern_kit/test/conformance/ccv3_conformance_test.rb`
  - Zip safety limits for BYAF/CHARX (zip-slip/zip-bomb guardrails) (see `TavernKit::Archive::ZipReader`)
- **Integration tests (All)**:
  - `lib/tavern_kit/test/integration/silly_tavern_build_test.rb`
  - RisuAI end-to-end test: character + template + lore + CBS -> plan -> dialect messages

**Gate commands:**
- `cd lib/tavern_kit && bundle exec rake test`
- `cd lib/tavern_kit && bundle exec rake test:guardrails test:conformance test:integration`

**Deliverable:** All Wave 5 characterization tests passing (no skips for
implemented modules). Full ST + RisuAI parity verified. Rails integration
verified. `TavernKit::RisuAI.build()` runs end-to-end with CBS macros,
decorator-driven lorebook, regex scripts, and triggers all operational.

#### Deferred / Out of Scope (This Batch)

- RisuAI tokenizer suite (10+ tokenizers) beyond the Core pluggable interface.
- RisuAI plugin system and Lua hooks.
- .risum module import/export.
- **Lorebook import formats:** ST supports importing from Novel AI (detected by
  `lorebookVersion`), Agnai (detected by `kind === 'memory'`), and RisuAI
  (detected by `type === 'risu'`). TavernKit will focus on ST native +
  Character Book (CCv2/CCv3 embedded) formats; external format importers are
  low priority and can be added via pluggable importer interface if needed.

### Wave 6 -- Documentation, Hardening & Global Review

**Close-out wave.** Ship-ready polish: docs, test hardening, and consistency
reviews after the major feature work is complete.

#### 6a. Documentation (Write Last, Carefully)

| Task | Layer | Description |
|------|-------|-------------|
| README(s) | All | Finalize `lib/tavern_kit/README.md` + top-level usage snippets; clarify supported inputs/outputs and stability guarantees |
| Rails integration guide | All | Practical guide for the Rails rewrite: ST build vs RisuAI build, persistence model, and where app-owned I/O lives |
| Pipeline + observability guide | Core | Strict/debug mode, TraceCollector, stage names, “how to debug failures” playbook |
| Compatibility docs | ST + RisuAI | Update compatibility matrix and conformance rules with what is actually implemented |

#### 6b. Test Hardening

| Task | Layer | Description |
|------|-------|-------------|
| Reduce skipped tests | All | Drive characterization tests to green; remaining skips must have written rationale and follow-up issue |
| Add regression fixtures | ST + RisuAI | Hand-author fixtures derived from behavior (not copied); cover tricky edge cases discovered during implementation |
| Property/edge tests | Core | Budgeting, trimming, ordering, and forward-compat behavior under random-ish inputs |

#### 6c. Global Review / Cleanup

| Task | Layer | Description |
|------|-------|-------------|
| API consistency pass | All | Naming, option shapes, error semantics (warn vs raise), and deprecations |
| Store unification decision | Core | Revisit variable/state storage API naming + shape (ChatVariables vs Store). Evaluate whether ST vars/globalvars and RisuAI metadata should be represented as scoped Stores, and clarify lifecycles/persistence + replacement rules |
| Performance pass | Core | Token estimation hot paths, avoid expensive debug work unless instrumenter is enabled |
| Trace + fingerprint review | Core | Ensure trace contains enough to reproduce “why this prompt” decisions; confirm fingerprint stability for caching |
| Large-file split pass | ST + RisuAI | Split `SillyTavern::Lore::Engine`, `SillyTavern::Macro::V2Engine`, `RisuAI::CBS::Engine`, and `RisuAI::Triggers` into internal helpers to meet the 800 LOC guideline, without behavior changes |
| Regex safety hardening | ST | Review JS-regex handling for ReDoS risk; consider timeouts/limits for untrusted patterns (keep tolerant mode behavior) |
| Extract LRU cache helper | Core | Add a small bounded LRU cache helper (no ActiveSupport dependency) and reuse it for regex compilation caches (ST regex scripts) and other hot-path bounded caches (e.g., JS-regex conversion in lore scanning) |
| Micro-perf audit backlog | Core/ST | Consider bounded caching for regex conversions, token count memoization, and precomputed sort keys where hot paths justify it |
| RisuAI triggers adapters (optional) | RisuAI | If needed by downstream apps, add adapter/hooks for UI/DB effects (alerts/LLM/imggen/lorebook persistence) so TavernKit can stay prompt-building focused while still supporting parity |

#### 6d. CLI / Tools

| Task | Layer | Description |
|------|-------|-------------|
| CLI parity (optional) | ST/Core | Add `exe/tavern_kit` with the minimal “developer tools” commands used for debugging/validation (validate/extract/convert/embed cards, prompt preview, lore test). Keep fixtures hand-authored (no ST/RisuAI fixture copying). |

#### 6e. UI Directives + Examples (Optional)

TavernKit does not ship a UI, but downstream apps may want to implement a
RisuAI-like “interactive chat” experience (buttons, code blocks, file cards,
etc.). The goal of this section is to support those apps **without**
introducing UI/HTML into model-bound prompt building.

| Task | Layer | Description |
|------|-------|-------------|
| Display-bound parsing | RisuAI | Add a `RisuAI::UI.parse(text, runtime:, context:)` helper that runs CBS in “visualize/display” semantics, but returns `{ text:, directives: [...] }` instead of HTML. |
| Model-bound sanitization | Core/RisuAI | Add a helper/middleware to ensure UI/HTML never enters model-bound prompt output; optionally preserve UI macro placeholders for post-processing. |
| Runtime sync contract | Core | Document and enforce that all app-owned state (global prompts/toggles/DB-derived values) is injected via `runtime.metadata` / runtime stores. Add conformance tests to prevent “hidden DB access” regressions. |
| Examples / PoC | All | Add hand-authored examples (not fixture copies) showing an interactive guide + VN-like branching using `directives` + runtime synchronization. |

**Deliverable:** Documentation is complete and aligned with the implemented
behavior; test suite is stable with minimal skips; APIs are consistent and
the system is ready for Rails app rewrite integration.

## API Design Direction

### Entry points

```ruby
# SillyTavern convenience (most common usage)
plan = TavernKit::SillyTavern.build do
  character my_char
  user my_user
  preset my_preset       # SillyTavern::Preset
  history chat_history
  lore_books [world_info]
  message "Hello!"
end

# Generic (explicit pipeline, for custom or RisuAI usage)
plan = TavernKit.build(pipeline: my_pipeline) do
  character my_char
  user my_user
  message "Hello!"
end

# RisuAI convenience (Wave 5)
plan = TavernKit::RisuAI.build do
  character my_char
  user my_user
  template_cards my_template     # RisuAI promptTemplate
  message "Hello!"
end
```

### Output conversion (Core -- platform-agnostic)

```ruby
# Dialects by symbol (default: :openai)
messages = plan.to_messages(dialect: :anthropic)
messages = plan.to_messages(dialect: :openai, squash_system_messages: true)
```

### Standalone tool usage (by Rails app)

```ruby
# ST Macro expansion for first messages
engine = TavernKit::SillyTavern::Macro::V2Engine.new
env = TavernKit::SillyTavern::Macro::Environment.new(
  character: my_char, user: my_user
)
expanded = engine.expand(template, environment: env)

# Core token estimation for UI
estimator = TavernKit::TokenEstimator.default
count = estimator.estimate(text)
count = estimator.estimate(text, model_hint: "gpt-4o")

# ST Lore activation for preview
lore_engine = TavernKit::SillyTavern::Lore::Engine.new(match_whole_words: true)
input = TavernKit::SillyTavern::Lore::ScanInput.new(
  messages: chat_messages, books: lore_books, budget: 2048,
  scan_context: { persona: persona_text }
)
results = lore_engine.scan(input)
```

### Extension points

```ruby
# Custom ChatHistory adapter (Core protocol)
class MessageHistory < TavernKit::ChatHistory::Base
  def each(&block) = ...
  def size = ...
end

# ST Pipeline customization
plan = TavernKit::SillyTavern.build do
  character my_char
  user my_user
  insert_before :compilation, MyTranslationMiddleware
  message "Hello!"
end
```

### Error handling

```ruby
# Core errors (current)
TavernKit::Error                     # Base
TavernKit::InvalidCardError          # Card parsing failure
TavernKit::UnsupportedVersionError   # Unsupported card format/version
TavernKit::Png::ParseError
TavernKit::Png::WriteError
TavernKit::Lore::ParseError
TavernKit::StrictModeError           # Warnings are errors

TavernKit::PipelineError             # Middleware chain failure w/ stage name
TavernKit::MaxTokensExceededError    # Token budget / soft-limit overflow (MaxTokensMiddleware / Trimmer)

# ST-specific errors
TavernKit::SillyTavern::MacroError
TavernKit::SillyTavern::InvalidInstructError
TavernKit::SillyTavern::LoreParseError

# Archive/container errors (Core)
TavernKit::Archive::ZipError
TavernKit::Archive::ByafParseError
TavernKit::Archive::CharXParseError
```

**Strict mode (standardized):**
- Purpose: **tests + debugging** (not production). Catch "quality" issues early.
- Definition: `Prompt::Context#warn` becomes fatal. Any `ctx.warn(...)` raises `TavernKit::StrictModeError`.
- Enable:
  - Pipeline DSL: `strict(true)` inside `TavernKit.build { ... }`
  - Or direct: `TavernKit::Prompt::Context.new(strict: true)`

## File Organization Target

```
lib/tavern_kit/
  lib/
    tavern_kit.rb                    # Entry point (requires all)
    tavern_kit/
      version.rb

      # === CORE: Value Objects & Data Models ===
      character.rb
      character_card.rb
      ingest.rb                      # Ingest (file adapters)       [Wave 2]
      ingest/
      character/                     # Character schemas
      user.rb
      participant.rb

      # === CORE: Interface Protocols ===            [Wave 2]
      preset/
        base.rb                      # Preset::Base interface
      lore/
        engine/
          base.rb                    # Lore::Engine::Base interface
        scan_input.rb                # Lore::ScanInput (subclassed by ST/RisuAI)
        book.rb                      # Lore::Book data
        entry.rb                     # Lore::Entry data (shared + extensions Hash)
        result.rb                    # Lore::Result data
      macro/
        engine/
          base.rb                    # Macro::Engine::Base (#expand with environment:)
        environment/
          base.rb                    # Macro::Environment::Base (character_name, user_name, var access)
        registry/
          base.rb                    # Macro::Registry::Base (#register with **metadata)
      hook_registry/
        base.rb                      # HookRegistry::Base interface
      injection_registry/
        base.rb                      # InjectionRegistry::Base interface
        entry.rb

      # === CORE: Platform-Agnostic Implementations ===
      chat_history.rb                # ChatHistory::Base
      chat_history/
        in_memory.rb                 # ChatHistory::InMemory
      chat_variables.rb              # ChatVariables::Base
      chat_variables/
        in_memory.rb                 # ChatVariables::InMemory
      token_estimator.rb             # TokenEstimator
      trim_report.rb                 # TrimReport + TrimResult
      trimmer.rb                     # Trimmer                     [Wave 4]
      prompt/
        pipeline.rb                  # Pipeline
        dsl.rb                       # DSL
        plan.rb                      # Plan
        context.rb                   # Context
        trace.rb                     # Trace/build report
        instrumenter.rb              # Instrumenter interface
        block.rb                     # Block
        message.rb                   # Message
        prompt_entry.rb              # PromptEntry
        middleware/
          base.rb                    # Middleware base
          max_tokens.rb              # MaxTokensMiddleware          [Wave 4]
        dialects/                    # Dialect adapters            [Wave 4]
          base.rb
          openai.rb
          anthropic.rb
          google.rb
          cohere.rb
          ai21.rb
          mistral.rb
          xai.rb
          text.rb

      # === CORE: Utilities ===
      archive/
        zip_reader.rb
        byaf.rb
        charx.rb
      png/
        parser.rb
        writer.rb
      text/
        pattern_matcher.rb
      coerce.rb
      utils.rb
      constants.rb
      errors.rb

      # === SILLY TAVERN: ST-Specific Implementation ===
      silly_tavern/
        build.rb                     # TavernKit::SillyTavern.build()
        pipeline.rb                  # Default 9-stage chain        [Wave 4]
        preset.rb                    # SillyTavern::Preset
        preset/
          st_importer.rb             # ST preset JSON import
        instruct.rb                  # SillyTavern::Instruct
        context_template.rb          # SillyTavern::ContextTemplate
        examples_parser.rb           # <START> marker parsing
        expander_vars.rb             # Context -> macro vars
        group_context.rb
        hook_registry.rb
        injection_registry.rb
        injection_planner.rb
        in_chat_injector.rb
        lore/
          engine.rb
          decorator_parser.rb
          timed_effects.rb
          key_list.rb
          scan_input.rb
          world_info_importer.rb
          entry_extensions.rb
        macro/
          v1_engine.rb
          v2_engine.rb
          registry.rb
          environment.rb
          invocation.rb
          flags.rb
          preprocessors.rb
          packs/
            silly_tavern.rb
            silly_tavern/
              *.rb
        middleware/
          hooks.rb
          lore.rb
          entries.rb
          pinned_groups.rb
          injection.rb
          compilation.rb
          macro_expansion.rb
          plan_assembly.rb
          trimming.rb

    # === RISUAI: RisuAI-Specific Implementation === [Wave 5]
    risu_ai/
      risu_ai.rb                     # RisuAI entry, RisuAI.build()
      cbs/
        engine.rb                    # CBS parser (10 block types, stack-based evaluation)
        macros.rb                    # 130+ built-in CBS macros (registry + handlers)
        environment.rb               # RisuAI::CBS::Environment (extends Macro::Environment::Base; adds chat_index, toggles, metadata, modules, assets)
      lore/
        engine.rb                    # RisuAI lore (decorator-driven, iterative loop)
        decorator_parser.rb          # 30+ RisuAI decorators
        scan_input.rb                # RisuAI::Lore::ScanInput (extends Core; adds chat_variables, message_index, recursive_scanning)
      memory/
        engine.rb                    # HypaMemory/SupaMemory integration
      regex_scripts.rb               # customscript processing
      triggers.rb                    # v1+v2 triggers
      template_cards.rb              # Template card system
      pipeline.rb                    # RisuAI middleware chain
```

## Metrics

| Metric | Wave 1 (current) | Target (Wave 5) |
|--------|-------------------|------------------|
| Gem LOC | ~2,000 | ~13,000-15,000 |
| Test files | 25 | 90+ |
| Test cases | 206 (30 pending) | 1,000+ (0 pending) |
| Code coverage | ~35% | >= 80% |
| Pending characterization tests | 30 | 0 |
| ST parity | Partial (cards only) | Full (aligned to v1.15.0) |
| ST preset fields | 0 | 60+ (sampling, budget, prompts, templates, nudges) |
| ST macro count | 0 | ~81 (incl. aliases) |
| ST V2 features | 0 | Scoped blocks, variable shorthand (16 ops), `{{if}}`/`{{else}}`, flags |
| ST Lore entry fields | 0 | 40+ fields (incl. `match*`, `characterFilter*`, `triggers`) |
| Context template placeholders | 0 | 9 (system, description, personality, scenario, persona, wiBefore/wiAfter, anchorBefore/After) |
| Persona description positions | 0 | 5 (IN_PROMPT, TOP_AN, BOTTOM_AN, AT_DEPTH, NONE) |
| Extension prompt types | 0 | 4 (NONE, IN_PROMPT, IN_CHAT, BEFORE_PROMPT) |
| Group activation strategies | 0 | 4 (NATURAL, LIST, MANUAL, POOLED) |
| Continue/Impersonate modes | 0 | Nudges, prefill, postfix types, Claude-specific impersonation |
| Stopping string sources | 0 | 4 (names, instruct, context, custom) |
| RisuAI parity | None | CBS (130+ macros, 10 blocks, 13+ operators) + Lorebook (30+ decorators, injection graph) + Regex (6 types, 7 directives) + Triggers (v1: 16 effects + v2: 60+ effects) |
| RisuAI CBS block types | 0 | 10 (#when, #if, #each, #func, #escape, #puredisplay, #pure, #code, #if_pure, :else) |
| RisuAI CBS built-in macros | 0 | 130+ (15 categories with aliases) |
| RisuAI #when operators | 0 | 13+ (is/isnot, comparisons, and/or/not, var/toggle, vis/tis) |
| RisuAI lorebook decorators | 0 | 30+ (position, activation, keys, recursion, injection) |
| RisuAI trigger v2 effects | 0 | 60+ (control flow, vars, strings, arrays, dicts, chat, lorebook CRUD, UI) |
| RisuAI prompt item types | 0 | 6 (Plain, Typed, Chat, AuthorNote, ChatML, Cache) |
| RisuAI memory system | 0 | HypaMemory V1/V2/V3 + SupaMemory |
| Dialect formats | 0 | 8 |
| Middleware stages (ST) | 1 (base) | 9 + base |
| Platform layers | 1 (Core) | 3 (Core + ST + RisuAI) |

## Reference

- Core interface design: `docs/rewrite/core-interface-design.md`
- ST alignment delta: `docs/rewrite/st-alignment-delta-v1.15.0.md`
- RisuAI alignment delta: `docs/rewrite/risuai-alignment-delta.md`
- ST/RisuAI parity checklist: `docs/rewrite/st-risuai-parity.md`
