# Vibe Tavern Rewrite

## TL;DR

> **Quick Summary**: Rewrite the reference TavernKit gem (`resources/tavern_kit/`) and Playground Rails app (`resources/tavern_kit/playground/`) into clean, production-ready code with unified style, maximum modularity, and Rails 8.2/Ruby 4.0 best practices.
>
> **Deliverables**:
> - `lib/tavern_kit/`: Complete SillyTavern-compatible prompt building gem (framework-agnostic)
> - `lib/easy_talk/`: Forked EasyTalk with Rails 8.2 type system integration
> - `app/`: Rails application with models, services, controllers, and real-time chat UI
>
> **Estimated Effort**: XL (12-16 weeks)
> **Parallel Execution**: YES - 5 waves with 2-4 parallel tasks per wave
> **Critical Path**: Foundation → Pipeline → Advanced Features → Rails Integration → Frontend

---

## Context

### Original Request
Rewrite the reference implementations at `resources/tavern_kit` (gem) and `resources/tavern_kit/playground` (Rails app) into clean, production-ready code. Goals:
- Eliminate vibe-coding inconsistencies
- Unify code style
- Maximize modularity for source-level reuse
- Use Rails 8.2 + Ruby 4.0 modern features
- Align behavior with SillyTavern (primary) and RisuAI (secondary)

### Interview Summary
**Key Discussions**:
- **JSON Serialization**: Fork EasyTalk to integrate with Rails 8.2 type system
- **Rails Version**: Edge (8.2.0.alpha) is acceptable, Gemfile already pins to rails/rails main
- **Testing Strategy**: Minitest + characterization tests - port reference tests, add characterization tests before refactoring (initial ST/RisuAI scaffolds are skipped until implementation)
- **Parity Priority**: SillyTavern is the primary source of truth when behaviors conflict; RisuAI parity/tests are backlog until ST parity is stable

**Research Findings**:
- TavernKit uses 9-stage middleware pipeline (Rack-like): Hooks → Lore → Entries → PinnedGroups → Injection → Compilation → MacroExpansion → PlanAssembly → Trimming
- 50+ ST-compatible macros in `Macro::Packs::SillyTavern`
- EasyTalk + EasyTalkCoder pattern with `x-ui`, `x-storage` JSON Schema extensions
- Playground uses adapter pattern: `PromptBuilding::*Adapter` converts Rails models to TavernKit domain objects
- Reference implementation is well-documented at `resources/tavern_kit/ARCHITECTURE.md`

### Metis Review
**Identified Gaps** (addressed):
- Migration strategy questions → Deferred (no existing data in main repo)
- SillyTavern version pinning → Align to current ST behavior using `resources/SillyTavern` snapshot as reference (no commit pin)
- Macro scope for Phase 1 → Limited to identity + character field macros
- Output dialect scope for Phase 2 → Limited to :openai, :anthropic, :text
- Group chat scope → Deferred to Phase 4+

---

## Work Objectives

### Core Objective
Rewrite the TavernKit gem and Playground Rails app into clean, production-ready code that maintains SillyTavern behavioral parity while following Ruby/Rails best practices.

### Concrete Deliverables
- `lib/tavern_kit/lib/tavern_kit/` - Complete gem implementation
- `lib/easy_talk/` - Forked EasyTalk with Rails 8.2 integration
- `app/models/` - Character, Space, Preset, Conversation, Message models
- `app/services/` - PromptBuilder, adapters, conversation services
- `app/controllers/` - API and web controllers
- `app/javascript/` - Stimulus controllers for chat UI
- `app/channels/` - ActionCable for real-time streaming
- `test/` - Comprehensive Minitest suite

### Definition of Done
- [ ] `cd lib/tavern_kit && bundle exec rake test` passes with 0 failures
- [ ] `bin/ci` passes (lint + security + full test suite)
- [ ] Character card V2/V3 round-trip preserves all data
- [ ] Prompt output matches reference implementation for same inputs
- [ ] Real-time chat streaming works end-to-end

### Must Have
- SillyTavern-compatible macro expansion (50+ macros)
- Character Card V2/V3 loading and export
- PNG metadata extraction and embedding
- 9-stage middleware pipeline architecture
- World Info / Lorebook with keywords, budget, recursion, timed effects
- Prompt Manager with ordered entries and conditions
- Context trimming (examples → lore → history)
- Output dialects: OpenAI, Anthropic, Text (minimum)
- Rails models with EasyTalk JSON serialization
- ActionCable-based LLM response streaming

### Must NOT Have (Guardrails)
- **No Rails dependencies in gem**: `lib/tavern_kit/` must be framework-agnostic
- **No feature invention**: Only implement features present in SillyTavern reference
- **No undocumented EasyTalk changes**: All fork changes logged in `lib/easy_talk/FORK_CHANGES.md`
- **No placeholder messages**: Use ephemeral typing indicators, not persisted placeholder messages
- **No group chat in Phase 1-3**: Multi-character group chat is Phase 4+
- **No i18n in Phase 1-4**: English-only, i18n middleware is Phase 5

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (Minitest configured)
- **User wants tests**: TDD / Characterization-first
- **Framework**: Minitest + fixtures (per AGENTS.md)

### TDD Workflow

Each TODO follows characterization-first then TDD:

**Task Structure:**
1. **CHARACTERIZE**: Port reference tests or write characterization tests
   - Test file: `test/[layer]/[name]_test.rb` or `lib/tavern_kit/test/tavern_kit/[name]_test.rb`
   - Test command: `bin/rails test [file]` or `cd lib/tavern_kit && bundle exec rake test`
   - Expected: Tests describe current reference behavior
2. **RED**: Run tests against new implementation
   - Expected: FAIL (tests exist, implementation doesn't)
3. **GREEN**: Implement minimum code to pass
   - Expected: PASS
4. **REFACTOR**: Clean up while keeping green
   - Expected: PASS (still)

### Automated Verification

**For gem code** (using Bash):
```bash
cd lib/tavern_kit && bundle exec rake test
# Assert: 0 failures, 0 errors
```

**For Rails code** (using Bash):
```bash
bin/rails test
# Assert: 0 failures, 0 errors
```

**For full CI** (using Bash):
```bash
bin/ci
# Assert: Exit code 0
```

**For character card round-trip** (using Bash):
```bash
bin/rails runner "
  card = TavernKit::CharacterCard.load('test/fixtures/files/seraphina.png')
  v2 = TavernKit::CharacterCard.export_v2(card)
  v3 = TavernKit::CharacterCard.export_v3(card)
  roundtrip = TavernKit::CharacterCard.load(v2)
  puts roundtrip.name == card.name ? 'PASS' : 'FAIL'
"
# Assert: Output is "PASS"
```

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Foundation - Start Immediately):
├── Task 1: Port gem test suite (characterization)
├── Task 2: Gem error hierarchy + Data.define models
└── Task 3: EasyTalk fork documentation + Rails 8.2 integration plan

Wave 2 (Character Cards - After Wave 1):
├── Task 4: Character Card V2/V3 loading
├── Task 5: PNG parser/writer
└── Task 6: Basic macro system (identity macros)

Wave 3 (Pipeline - After Wave 2):
├── Task 7: Middleware architecture (Pipeline, Context, Base)
├── Task 8: Core middleware (Hooks, Entries, Compilation, PlanAssembly)
├── Task 9: Preset system with Prompt Manager entries
└── Task 10: Output dialects (OpenAI, Anthropic, Text)

Wave 4 (Advanced + Rails - After Wave 3):
├── Task 11: Full macro pack (time, random, variables)
├── Task 12: World Info engine (keywords, budget, recursion)
├── Task 13: Context trimming
├── Task 14: EasyTalk Rails integration + EasyTalkCoder
└── Task 15: Core Rails models (Character, Space, Preset)

Wave 5 (Integration + Frontend - After Wave 4):
├── Task 16: Conversation/Message models
├── Task 17: PromptBuilder service with adapters
├── Task 18: API controllers
├── Task 19: ActionCable streaming
└── Task 20: Stimulus controllers for chat UI

Critical Path: Task 1 → Task 4 → Task 7 → Task 8 → Task 10 → Task 17 → Task 19
Parallel Speedup: ~50% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 4, 5, 6 | 2, 3 |
| 2 | None | 4, 5, 6, 7 | 1, 3 |
| 3 | None | 14 | 1, 2 |
| 4 | 1, 2 | 7, 9, 15 | 5, 6 |
| 5 | 1, 2 | None | 4, 6 |
| 6 | 1, 2 | 8, 11 | 4, 5 |
| 7 | 4 | 8, 9, 10 | None |
| 8 | 6, 7 | 10, 12, 13 | 9 |
| 9 | 4, 7 | 15 | 8 |
| 10 | 8 | 17 | None |
| 11 | 6 | None | 12, 13, 14 |
| 12 | 8 | None | 11, 13, 14 |
| 13 | 8 | None | 11, 12, 14 |
| 14 | 3 | 15 | 11, 12, 13 |
| 15 | 4, 9, 14 | 16, 17 | None |
| 16 | 15 | 17, 19 | None |
| 17 | 10, 15, 16 | 18, 19 | None |
| 18 | 17 | None | 19, 20 |
| 19 | 16, 17 | 20 | 18 |
| 20 | 19 | None | 18 |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 2, 3 | `delegate_task(category="unspecified-high", load_skills=["rails-tdd-minitest"], ...)` |
| 2 | 4, 5, 6 | `delegate_task(category="unspecified-high", load_skills=["rails-tdd-minitest"], ...)` |
| 3 | 7, 8, 9, 10 | `delegate_task(category="unspecified-high", load_skills=["rails-tdd-minitest"], ...)` |
| 4 | 11-15 | `delegate_task(category="unspecified-high", load_skills=["rails-tdd-minitest", "vibe-tavern-guardrails"], ...)` |
| 5 | 16-20 | `delegate_task(category="visual-engineering", load_skills=["rails-tdd-minitest", "vibe-tavern-guardrails"], ...)` |

---

## TODOs

### Fixture Creation Strategy

**Gem fixtures** (created in Task 1):
- `lib/tavern_kit/test/fixtures/files/` - Sample PNG and JSON character cards

**Rails fixtures** (created in Task 15):
- `test/fixtures/users.yml` - Test users
- `test/fixtures/characters.yml` - Test characters
- `test/fixtures/spaces.yml` - Test spaces (STI types)
- `test/fixtures/presets.yml` - Test presets

**Later fixtures** (created in Task 16):
- `test/fixtures/conversations.yml` - Test conversations
- `test/fixtures/messages.yml` - Test messages

---

### Phase 1: Foundation

- [ ] 1. Port gem test suite (characterization)

  **What to do**:
  - Copy test files from `resources/tavern_kit/test/` to `lib/tavern_kit/test/`
  - Adapt test helper to work with stub gem structure
  - Document which tests pass/fail against stub
  - Create test fixtures directory with sample cards

  **Must NOT do**:
  - Implement any production code yet
  - Modify tests to pass (characterization captures current behavior)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Test porting requires careful attention but isn't visual or architectural
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: Test framework conventions and patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3)
  - **Blocks**: Tasks 4, 5, 6
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/test/test_helper.rb` - Test helper setup pattern
  - `resources/tavern_kit/test/test_character_card.rb` - Character card test structure
  - `resources/tavern_kit/test/test_character.rb` - Character model tests

  **Test References**:
  - `resources/tavern_kit/test/*.rb` - Root-level tests (test_character_card.rb, test_character.rb, etc.)
  - `resources/tavern_kit/test/lore/*.rb` - Lore subsystem tests
  - `resources/tavern_kit/test/spec_conformance/*.rb` - Conformance tests

  **WHY Each Reference Matters**:
  - `test_helper.rb` shows minitest configuration and helper methods needed
  - `test_character_card.rb` demonstrates the testing style and assertion patterns used (note: tests are at root level, not in subdirectory)

  **Acceptance Criteria**:

  ```bash
  # Test files exist
  ls lib/tavern_kit/test/tavern_kit/*.rb | wc -l
  # Assert: Returns >= 10 (multiple test files ported)

  # Test helper loads without error
  cd lib/tavern_kit && ruby -e "require_relative 'test/test_helper'"
  # Assert: Exit code 0

  # Tests run (failures expected at this stage)
  cd lib/tavern_kit && bundle exec rake test 2>&1 | tail -5
  # Assert: Output shows test count > 0
  ```

  **Commit**: YES
  - Message: `test(tavern_kit): port reference test suite for characterization`
  - Files: `lib/tavern_kit/test/**/*`
  - Pre-commit: N/A (tests expected to fail)

---

- [ ] 2. Gem error hierarchy + Data.define models

  **What to do**:
  - Create `lib/tavern_kit/lib/tavern_kit/errors.rb` with error class hierarchy
  - Create core domain models using `Data.define`:
    - `TavernKit::Character` (V3 superset fields)
    - `TavernKit::User` (Participant implementation)
    - `TavernKit::Preset` (prompt configuration)
    - `TavernKit::Instruct` (instruct mode settings)
    - `TavernKit::ContextTemplate` (story string assembly)
  - Implement `Participant` interface module

  **Must NOT do**:
  - Implement CharacterCard loading logic (that's Task 4)
  - Implement macro expansion (that's Task 6)
  - Add any Rails dependencies

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Core domain modeling requires careful design
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow for model tests

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3)
  - **Blocks**: Tasks 4, 5, 6, 7
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/character.rb` - Character Data.define pattern
  - `resources/tavern_kit/lib/tavern_kit/user.rb` - User implementation
  - `resources/tavern_kit/lib/tavern_kit/preset.rb` - Preset fields and defaults
  - `resources/tavern_kit/lib/tavern_kit/errors.rb` - Error hierarchy pattern

  **API/Type References**:
  - `resources/tavern_kit/ARCHITECTURE.md:178-216` - Character fields table (V3 superset)
  - `resources/tavern_kit/ARCHITECTURE.md:689-718` - Instruct fields

  **WHY Each Reference Matters**:
  - `character.rb` shows how Data.define is used with optional fields and defaults
  - `errors.rb` defines the exception hierarchy (ParseError, ValidationError, etc.)
  - ARCHITECTURE.md tables define the exact fields needed for ST parity

  **Acceptance Criteria**:

  ```bash
  # Error classes defined (matching reference: errors.rb)
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    puts TavernKit::Error.ancestors.include?(StandardError)
    puts defined?(TavernKit::InvalidCardError)
    puts defined?(TavernKit::UnsupportedVersionError)
    puts defined?(TavernKit::StrictModeError)
    puts defined?(TavernKit::Png::ParseError)
  "
  # Assert: All 5 output lines are "true"

  # Character model works
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    char = TavernKit::Character.new(name: 'Test')
    puts char.name
    puts char.respond_to?(:description)
  "
  # Assert: Output is "Test" and "true"

  # User implements Participant
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    user = TavernKit::User.new(name: 'Alice')
    puts user.respond_to?(:name)
    puts user.respond_to?(:persona_text)
  "
  # Assert: Both output "true"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): add error hierarchy and core Data.define models`
  - Files: `lib/tavern_kit/lib/tavern_kit/*.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 3. EasyTalk fork documentation + Rails 8.2 integration plan

  **What to do**:
  - Validate and update fork docs to reflect implemented `ActiveModel::Type` adapter
  - Document current EasyTalk capabilities and limitations
  - Verify/refresh Rails 8.2 integration plan (edge behavior)
  - Plan `x-ui` and `x-storage` JSON Schema extension support
  - Run EasyTalk tests to establish baseline

  **Must NOT do**:
  - Remove or regress existing EasyTalk Rails integration
  - Break existing EasyTalk functionality

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Documentation and design planning task
  - **Skills**: [`vibe-tavern-guardrails`]
    - `vibe-tavern-guardrails`: Project-specific constraints

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Task 14
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `lib/easy_talk/` - Current EasyTalk fork source
  - `resources/tavern_kit/playground/app/models/conversation_settings/base.rb` - EasyTalk extensions used

  **Documentation References**:
  - `resources/rails/activemodel/lib/active_model/schematized_json.rb` - Rails 8.2 has_json implementation
  - `resources/tavern_kit/playground/app/models/concerns/easy_talk_coder.rb` - Current coder pattern

  **WHY Each Reference Matters**:
  - Current EasyTalk code is the baseline for fork changes
  - `schematized_json.rb` shows Rails 8.2 type casting approach to emulate
  - `conversation_settings/base.rb` shows `x-ui`/`x-storage` extension patterns needed

  **Acceptance Criteria**:

  ```bash
  # FORK_CHANGES.md exists and has content
  cat lib/easy_talk/FORK_CHANGES.md | head -20
  # Assert: Contains "# EasyTalk Fork Changes"

  # Document lists planned integrations
  grep -c "Rails 8.2" lib/easy_talk/FORK_CHANGES.md
  # Assert: Returns >= 1

  # EasyTalk tests still pass
  cd lib/easy_talk && bundle exec rake test
  # Assert: 0 failures
  ```

  **Commit**: YES
  - Message: `docs(easy_talk): update fork changes and Rails 8.2 integration plan`
  - Files: `lib/easy_talk/FORK_CHANGES.md`, `lib/easy_talk/README.md`, docs as needed
  - Pre-commit: `cd lib/easy_talk && bundle exec rake test`

---

### Phase 2: Character Cards

- [ ] 4. Character Card V2/V3 loading

  **What to do**:
  - Implement `TavernKit::CharacterCard.load(input)` accepting PNG, JSON, Hash
  - Implement version detection (`:v1`, `:v2`, `:v3`, `:unknown`)
  - Implement V2→Character and V3→Character conversion
  - Implement `export_v2` and `export_v3` methods
  - Handle strict parsing (raise `InvalidCardError` for malformed input, `UnsupportedVersionError` for V1 cards)
  - Preserve V3 fields in V2 `extensions["cc_extractor/v3"]`

  **Must NOT do**:
  - Implement PNG parsing (that's Task 5)
  - Implement macro expansion in card fields
  - Add validation beyond basic structure

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Complex data transformation logic
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: Tasks 7, 9, 15
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/character_card.rb` - Complete implementation (single file, includes loading + export + version detection)

  **Test References**:
  - `resources/tavern_kit/test/test_character_card.rb` - Character card test patterns

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:237-280` - CharacterCard methods table

  **WHY Each Reference Matters**:
  - `character_card.rb` is a single module with all loading/export/detection logic in one file
  - Version detection via `detect_version` method checks for `spec` field values
  - V3→V2 export preserves V3 fields in `extensions["cc_extractor/v3"]`

  **Acceptance Criteria**:

  ```bash
  # Load from JSON hash
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    card = TavernKit::CharacterCard.load({
      'spec' => 'chara_card_v2',
      'data' => {'name' => 'Test', 'description' => 'A test'}
    })
    puts card.name
    puts card.source_version
  "
  # Assert: Output is "Test" and ":v2"

  # Round-trip V2→V3→V2
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    original = TavernKit::CharacterCard.load({'spec'=>'chara_card_v2','data'=>{'name'=>'Test'}})
    v3 = TavernKit::CharacterCard.export_v3(original)
    v2 = TavernKit::CharacterCard.export_v2(TavernKit::CharacterCard.load(v3))
    puts v2['data']['name']
  "
  # Assert: Output is "Test"

  # Version detection
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    puts TavernKit::CharacterCard.detect_version({'spec'=>'chara_card_v2'})
    puts TavernKit::CharacterCard.detect_version({'spec'=>'chara_card_v3'})
  "
  # Assert: Output is ":v2" and ":v3"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement Character Card V2/V3 loading and export`
  - Files: `lib/tavern_kit/lib/tavern_kit/character_card.rb`, `lib/tavern_kit/lib/tavern_kit/character_card/*.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 5. PNG parser/writer

  **What to do**:
  - Implement `TavernKit::Png::Parser` for text chunk extraction
  - Support both PNG and APNG formats
  - Extract `chara` (V2) and `ccv3` (V3) text chunks
  - Handle base64 decoding of chunk content
  - Implement `TavernKit::Png::Writer` for embedding character data

  **Must NOT do**:
  - Implement image manipulation (only metadata)
  - Support non-PNG formats (JPG, WebP)
  - Add external image processing dependencies

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Binary format parsing requires precision
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 6)
  - **Blocks**: None (optional for Phase 1)
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/png/parser.rb` - Parser implementation (module with module_function API, not a class)
  - `resources/tavern_kit/lib/tavern_kit/png/writer.rb` - Writer implementation (module with module_function API)

  **Test References**:
  - `resources/tavern_kit/test/png_writer_test.rb` - PNG writer test patterns

  **Design Note**:
  - Reference uses `module TavernKit::Png::Parser` with `module_function` - decide whether to keep this pattern or use class-based API. Document choice explicitly.

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:47` - Png::Parser/Writer responsibilities

  **WHY Each Reference Matters**:
  - `parser.rb` shows PNG chunk iteration and text chunk extraction
  - `writer.rb` shows how to embed both V2 and V3 chunks simultaneously

  **Acceptance Criteria**:

  **Fixture Prerequisite**: Task 1 must create `lib/tavern_kit/test/fixtures/files/sample.png` (any valid PNG with or without character data)

  ```bash
  # Parser extracts text chunks (using module_function API as in reference)
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    # Module-level API matching reference implementation
    chunks = TavernKit::Png::Parser.extract_text_chunks('test/fixtures/files/sample.png')
    puts chunks.is_a?(Array)
  "
  # Assert: Output is "true"

  # Writer module defined
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    puts defined?(TavernKit::Png::Writer)
    puts TavernKit::Png::Writer.respond_to?(:embed_card)
  "
  # Assert: Output is "constant" and "true"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement PNG parser and writer for character cards`
  - Files: `lib/tavern_kit/lib/tavern_kit/png/*.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 6. Basic macro system (identity macros)

  **What to do**:
  - Implement `TavernKit::MacroRegistry` for macro registration
  - Implement `TavernKit::Macro::SillyTavernV2::Engine` (parser-based)
  - Implement basic identity macros: `{{char}}`, `{{user}}`, `{{persona}}`
  - Implement character field macros: `{{description}}`, `{{personality}}`, `{{scenario}}`
  - Support case-insensitive matching
  - Keep unknown macros as-is (passthrough)

  **Must NOT do**:
  - Implement time/date macros (Phase 3)
  - Implement random/dice macros (Phase 3)
  - Implement variable macros (Phase 3)
  - Implement V1 engine (legacy, lower priority)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Parser-based expansion is complex
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Tasks 8, 11
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/macro/silly_tavern_v2/engine.rb` - V2 engine
  - `resources/tavern_kit/lib/tavern_kit/macro_registry.rb` - Registry pattern
  - `resources/tavern_kit/lib/tavern_kit/macro/packs/silly_tavern.rb` - Macro definitions

  **Test References**:
  - `resources/tavern_kit/test/macro_registry_test.rb` - Macro registry test patterns
  - `resources/tavern_kit/test/macro_pipeline_test.rb` - Macro pipeline test patterns
  - `resources/tavern_kit/test/test_instruct_macros.rb` - Instruct macro tests

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:639-668` - Macro categories table

  **WHY Each Reference Matters**:
  - `engine.rb` shows parser-based expansion with nesting support
  - `macro_registry.rb` shows registration API
  - `packs/silly_tavern.rb` shows macro implementation patterns (first 10 macros are identity/character)

  **Acceptance Criteria**:

  ```bash
  # Basic expansion works
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    engine = TavernKit::Macro::SillyTavernV2::Engine.new
    result = engine.expand('Hello {{char}}!', {char: 'Alice'})
    puts result
  "
  # Assert: Output is "Hello Alice!"

  # Case insensitive
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    engine = TavernKit::Macro::SillyTavernV2::Engine.new
    puts engine.expand('{{CHAR}}', {char: 'Alice'})
    puts engine.expand('{{Char}}', {char: 'Alice'})
  "
  # Assert: Both output "Alice"

  # Unknown macros preserved
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    engine = TavernKit::Macro::SillyTavernV2::Engine.new
    puts engine.expand('{{unknown}}', {})
  "
  # Assert: Output is "{{unknown}}"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement basic macro system with identity macros`
  - Files: `lib/tavern_kit/lib/tavern_kit/macro/**/*.rb`, `lib/tavern_kit/lib/tavern_kit/macro_registry.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

### Phase 3: Prompt Pipeline

- [ ] 7. Middleware architecture (Pipeline, Context, Base)

  **What to do**:
  - Implement `TavernKit::Prompt::Pipeline` with Rack-like middleware pattern
  - Implement `TavernKit::Prompt::Context` (mutable with `attr_accessor`, matching reference pattern)
  - Implement `TavernKit::Prompt::Middleware::Base` abstract class
  - Support `use`, `replace`, `insert_before`, `insert_after`, `remove` API
  - Create default pipeline with placeholder middleware

  **Must NOT do**:
  - Implement actual middleware logic (that's Task 8)
  - Implement output dialects (that's Task 10)
  - Add any Rails dependencies

  **Recommended Agent Profile**:
  - **Category**: `ultrabrain`
    - Reason: Architectural middleware pattern design
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (depends on Character model)
  - **Blocks**: Tasks 8, 9, 10
  - **Blocked By**: Task 4

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/prompt/pipeline.rb` - Pipeline implementation
  - `resources/tavern_kit/lib/tavern_kit/prompt/context.rb` - Context implementation
  - `resources/tavern_kit/lib/tavern_kit/prompt/middleware/base.rb` - Middleware base

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:955-1018` - Pipeline architecture diagram
  - `resources/tavern_kit/ARCHITECTURE.md:1019-1032` - Middleware components table

  **WHY Each Reference Matters**:
  - `pipeline.rb:50-62` shows middleware chain execution pattern
  - `context.rb` shows immutable `with` pattern for context updates
  - ARCHITECTURE.md has visual pipeline flow diagram

  **Acceptance Criteria**:

  ```bash
  # Pipeline accepts middleware
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    pipeline = TavernKit::Prompt::Pipeline.new
    class TestMiddleware < TavernKit::Prompt::Middleware::Base
      def before(ctx); ctx; end
    end
    pipeline.use(TestMiddleware)
    puts pipeline.middlewares.size
  "
  # Assert: Output is "1" (or more if default exists)

  # Context is mutable (matching reference pattern)
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    ctx = TavernKit::Prompt::Context.new(character: nil)
    ctx.user_message = 'Hello'
    puts ctx.user_message
    puts ctx.respond_to?(:character=)
    puts ctx.respond_to?(:plan=)
  "
  # Assert: Output is "Hello", "true", "true"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement middleware pipeline architecture`
  - Files: `lib/tavern_kit/lib/tavern_kit/prompt/pipeline.rb`, `lib/tavern_kit/lib/tavern_kit/prompt/context.rb`, `lib/tavern_kit/lib/tavern_kit/prompt/middleware/base.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 8. Core middleware (Hooks, Entries, Compilation, PlanAssembly)

  **What to do**:
  - Implement `Middleware::Hooks` (before_build/after_build callbacks)
  - Implement `Middleware::Entries` (filter/categorize prompt entries)
  - Implement `Middleware::Compilation` (compile entries to blocks)
  - Implement `Middleware::PlanAssembly` (create Prompt::Plan)
  - Implement `TavernKit::Prompt::Block` and `TavernKit::Prompt::Plan`
  - Wire default pipeline with these middleware

  **Must NOT do**:
  - Implement Lore middleware (that's Task 12)
  - Implement Trimming middleware (that's Task 13)
  - Implement PinnedGroups or Injection (Phase 3 advanced)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Core middleware implementation
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 9)
  - **Blocks**: Tasks 10, 12, 13
  - **Blocked By**: Tasks 6, 7

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/prompt/middleware/hooks.rb` - Hooks middleware
  - `resources/tavern_kit/lib/tavern_kit/prompt/middleware/entries.rb` - Entries middleware
  - `resources/tavern_kit/lib/tavern_kit/prompt/middleware/compilation.rb` - Compilation
  - `resources/tavern_kit/lib/tavern_kit/prompt/middleware/plan_assembly.rb` - Assembly
  - `resources/tavern_kit/lib/tavern_kit/prompt/block.rb` - Block model
  - `resources/tavern_kit/lib/tavern_kit/prompt/plan.rb` - Plan model

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:836-855` - Block attributes table
  - `resources/tavern_kit/ARCHITECTURE.md:871-887` - Plan output dialects

  **WHY Each Reference Matters**:
  - Each middleware file shows the `before`/`after` hook pattern
  - `block.rb` defines the Block struct with slot, priority, budget_group
  - `plan.rb` shows `to_messages` dialect conversion

  **Acceptance Criteria**:

  ```bash
  # Build produces a plan
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    char = TavernKit::Character.new(name: 'Test', description: 'A test character')
    user = TavernKit::User.new(name: 'Alice')
    ctx = TavernKit::Prompt::Context.new(character: char, user: user, user_message: 'Hello')
    result = TavernKit::Prompt::Pipeline.default.call(ctx)
    puts result.plan.is_a?(TavernKit::Prompt::Plan)
    puts result.plan.blocks.size > 0
  "
  # Assert: Both output "true"

  # Block has required attributes
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    block = TavernKit::Prompt::Block.new(role: :system, content: 'Test')
    puts block.respond_to?(:role)
    puts block.respond_to?(:content)
    puts block.respond_to?(:slot)
  "
  # Assert: All output "true"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement core middleware (Hooks, Entries, Compilation, PlanAssembly)`
  - Files: `lib/tavern_kit/lib/tavern_kit/prompt/middleware/*.rb`, `lib/tavern_kit/lib/tavern_kit/prompt/block.rb`, `lib/tavern_kit/lib/tavern_kit/prompt/plan.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 9. Preset system with Prompt Manager entries

  **What to do**:
  - Enhance `TavernKit::Preset` with full configuration options
  - Implement `TavernKit::Prompt::PromptEntry` for Prompt Manager entries
  - Support pinned entries (main_prompt, chat_history, PHI, etc.)
  - Support custom entries with position, depth, order, conditions
  - Implement `partition_prompt_entries` for categorization

  **Must NOT do**:
  - Implement conditional activation evaluation (Phase 3 advanced)
  - Implement ST preset JSON loading (nice-to-have)
  - Add Rails model integration

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Configuration modeling
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 8)
  - **Blocks**: Task 15
  - **Blocked By**: Tasks 4, 7

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/preset.rb` - Preset implementation
  - `resources/tavern_kit/lib/tavern_kit/prompt/prompt_entry.rb` - PromptEntry model

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:748-790` - Preset fields mapping
  - `resources/tavern_kit/ARCHITECTURE.md:805-833` - PromptEntry attributes

  **WHY Each Reference Matters**:
  - `preset.rb` shows all configuration fields and ST mapping
  - `prompt_entry.rb` shows entry categorization logic
  - ARCHITECTURE.md has pinned group IDs list

  **Acceptance Criteria**:

  ```bash
  # Preset has required fields
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    preset = TavernKit::Preset.new(
      main_prompt: 'Test prompt',
      context_window_tokens: 8000
    )
    puts preset.main_prompt
    puts preset.context_window_tokens
  "
  # Assert: Output is "Test prompt" and "8000"

  # PromptEntry supports positions
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    entry = TavernKit::Prompt::PromptEntry.new(
      id: 'test',
      position: :in_chat,
      depth: 2,
      content: 'Test content'
    )
    puts entry.position
    puts entry.depth
  "
  # Assert: Output is ":in_chat" and "2"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement Preset and Prompt Manager entries`
  - Files: `lib/tavern_kit/lib/tavern_kit/preset.rb`, `lib/tavern_kit/lib/tavern_kit/prompt/prompt_entry.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 10. Output dialects (OpenAI, Anthropic, Text)

  **What to do**:
  - Implement `TavernKit::Prompt::Dialects::OpenAI` converter
  - Implement `TavernKit::Prompt::Dialects::Anthropic` converter
  - Implement `TavernKit::Prompt::Dialects::Text` converter
  - Add `Plan#to_messages(dialect:, **opts)` API
  - Support dialect-specific options (squash_system_messages, assistant_prefill)

  **Must NOT do**:
  - Implement other dialects (Google, Cohere, AI21, Mistral, xAI) - Phase 3+
  - Add LLM client integration (only format conversion)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Format transformation logic
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (depends on Plan)
  - **Blocks**: Task 17
  - **Blocked By**: Task 8

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/prompt/dialects.rb` - ALL dialects in single file (OpenAI, Anthropic, Text, Google, Cohere, etc.)

  **Test References**:
  - `resources/tavern_kit/test/test_text_dialect.rb` - Text dialect tests

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:877-887` - Output dialects table

  **WHY Each Reference Matters**:
  - `dialects.rb` is a single file containing all dialect converters as inner classes/modules
  - Anthropic has special `system` array handling (separate from messages)
  - Text dialect has instruct mode formatting with configurable sequences

  **Acceptance Criteria**:

  ```bash
  # OpenAI format
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    # Assuming Plan exists with blocks
    block = TavernKit::Prompt::Block.new(role: :user, content: 'Hello')
    plan = TavernKit::Prompt::Plan.new(blocks: [block])
    msgs = plan.to_messages(dialect: :openai)
    puts msgs.first[:role]
    puts msgs.first[:content]
  "
  # Assert: Output is "user" and "Hello"

  # Anthropic format
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    block = TavernKit::Prompt::Block.new(role: :system, content: 'System')
    plan = TavernKit::Prompt::Plan.new(blocks: [block])
    result = plan.to_messages(dialect: :anthropic)
    puts result.key?(:system)
    puts result.key?(:messages)
  "
  # Assert: Both output "true"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement output dialects (OpenAI, Anthropic, Text)`
  - Files: `lib/tavern_kit/lib/tavern_kit/prompt/dialects/*.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

### Phase 4: Advanced Features + Rails Integration

- [ ] 11. Full macro pack (time, random, variables)

  **What to do**:
  - Implement time/date macros: `{{date}}`, `{{time}}`, `{{weekday}}`, `{{isodate}}`, `{{datetimeformat}}`
  - Implement random macros: `{{random::a,b,c}}`, `{{pick::a,b,c}}`, `{{roll:dN}}`
  - Implement variable macros: `{{setvar::}}`, `{{getvar::}}`, `{{var::}}`, `{{addvar::}}`, `{{incvar::}}`, `{{decvar::}}`
  - Implement `TavernKit::ChatVariables::Base` and `InMemory` storage
  - Support deterministic `clock:` and `rng:` for testing

  **Must NOT do**:
  - Implement outlet macros (depends on World Info)
  - Add Rails-specific variable storage (that's Task 14)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Complex macro implementations
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 12, 13, 14)
  - **Blocks**: None
  - **Blocked By**: Task 6

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/macro/packs/silly_tavern.rb` - All macro implementations
  - `resources/tavern_kit/lib/tavern_kit/chat_variables.rb` - Variables storage

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:663-666` - Macro categories

  **WHY Each Reference Matters**:
  - `packs/silly_tavern.rb` has implementations for all 50+ macros
  - `chat_variables.rb` shows the Base interface and InMemory implementation

  **Acceptance Criteria**:

  ```bash
  # Time macro
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    require 'time'
    engine = TavernKit::Macro::SillyTavernV2::Engine.new(clock: -> { Time.new(2025, 1, 15, 10, 30) })
    puts engine.expand('{{isodate}}', {})
  "
  # Assert: Output contains "2025-01-15"

  # Random macro (seeded)
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    rng = Random.new(42)
    engine = TavernKit::Macro::SillyTavernV2::Engine.new(rng: rng)
    puts engine.expand('{{random::a,b,c}}', {}).match?(/[abc]/)
  "
  # Assert: Output is "true"

  # Variable macros
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    vars = TavernKit::ChatVariables::InMemory.new
    engine = TavernKit::Macro::SillyTavernV2::Engine.new
    engine.expand('{{setvar::x::hello}}', {}, local_store: vars)
    puts engine.expand('{{getvar::x}}', {}, local_store: vars)
  "
  # Assert: Output is "hello"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement full macro pack (time, random, variables)`
  - Files: `lib/tavern_kit/lib/tavern_kit/macro/packs/*.rb`, `lib/tavern_kit/lib/tavern_kit/chat_variables.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 12. World Info engine (keywords, budget, recursion)

  **What to do**:
  - Implement `TavernKit::Lore::Book` for lorebook container
  - Implement `TavernKit::Lore::Entry` for single entries
  - Implement `TavernKit::Lore::Engine` for evaluation:
    - Keyword matching (primary keys, Optional Filter)
    - Token budget with priority selection
    - Recursive scanning (max 10 depth)
    - Timed effects (sticky, cooldown, delay)
    - 8 insertion positions
  - Implement `Middleware::Lore` for pipeline integration

  **Must NOT do**:
  - Implement group scoring (nice-to-have)
  - Add Rails model integration

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Complex evaluation logic
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 11, 13, 14)
  - **Blocks**: None
  - **Blocked By**: Task 8

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/lore/book.rb` - Book container
  - `resources/tavern_kit/lib/tavern_kit/lore/entry.rb` - Entry model
  - `resources/tavern_kit/lib/tavern_kit/lore/engine.rb` - Evaluation engine
  - `resources/tavern_kit/lib/tavern_kit/prompt/middleware/lore.rb` - Middleware

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:905-930` - Lore Engine features

  **WHY Each Reference Matters**:
  - `engine.rb` has the complete evaluation algorithm with recursion limits
  - `entry.rb` shows all entry fields (keys, filter, timed effects)
  - `book.rb` shows source tracking and entry merging

  **Acceptance Criteria**:

  ```bash
  # Basic keyword matching
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    entry = TavernKit::Lore::Entry.new(keys: ['dragon'], content: 'Dragons breathe fire')
    book = TavernKit::Lore::Book.new(entries: [entry])
    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book, 'I see a dragon')
    puts result.selected.size
  "
  # Assert: Output is "1"

  # No match
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    entry = TavernKit::Lore::Entry.new(keys: ['dragon'], content: 'Dragons breathe fire')
    book = TavernKit::Lore::Book.new(entries: [entry])
    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book, 'I see a cat')
    puts result.selected.size
  "
  # Assert: Output is "0"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement World Info / Lore engine`
  - Files: `lib/tavern_kit/lib/tavern_kit/lore/*.rb`, `lib/tavern_kit/lib/tavern_kit/prompt/middleware/lore.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 13. Context trimming

  **What to do**:
  - Implement `TavernKit::Prompt::Trimmer` for budget enforcement
  - Implement eviction order: examples → lore → history
  - Use Block's `token_budget_group` and `priority` for eviction
  - Disable blocks in-place (set `enabled: false`)
  - Generate `trim_report` with eviction details
  - Implement `TavernKit::TokenEstimator` (tiktoken_ruby wrapper)
  - Implement `Middleware::Trimming` for pipeline

  **Must NOT do**:
  - Implement CharDiv4 estimator (testing only)
  - Add any LLM client integration

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Token budget algorithms
  - **Skills**: [`rails-tdd-minitest`]
    - `rails-tdd-minitest`: TDD workflow

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 11, 12, 14)
  - **Blocks**: None
  - **Blocked By**: Task 8

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/lib/tavern_kit/prompt/trimmer.rb` - Trimmer implementation
  - `resources/tavern_kit/lib/tavern_kit/token_estimator.rb` - Token counting
  - `resources/tavern_kit/lib/tavern_kit/prompt/middleware/trimming.rb` - Middleware

  **Documentation References**:
  - `resources/tavern_kit/ARCHITECTURE.md:889-901` - Trimmer description
  - `resources/tavern_kit/ARCHITECTURE.md:936-952` - TokenEstimator encodings

  **WHY Each Reference Matters**:
  - `trimmer.rb` shows eviction algorithm and trim_report generation
  - `token_estimator.rb` shows tiktoken_ruby integration

  **Acceptance Criteria**:

  ```bash
  # Token estimation works (API: estimate, not count)
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    estimator = TavernKit::TokenEstimator::TiktokenRuby.new
    count = estimator.estimate('Hello world')
    puts count > 0
    puts estimator.respond_to?(:tokenize)
  "
  # Assert: Both outputs are "true"

  # Trimmer disables blocks
  cd lib/tavern_kit && ruby -e "
    require_relative 'lib/tavern_kit'
    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: 'A' * 10000, token_budget_group: :examples)
    ]
    trimmer = TavernKit::Prompt::Trimmer.new(max_tokens: 100)
    result = trimmer.trim(blocks)
    puts result[:removed_example_blocks].size > 0 || blocks.first.enabled == false
  "
  # Assert: Output is "true"
  ```

  **Commit**: YES
  - Message: `feat(tavern_kit): implement context trimming with token estimation`
  - Files: `lib/tavern_kit/lib/tavern_kit/prompt/trimmer.rb`, `lib/tavern_kit/lib/tavern_kit/token_estimator.rb`, `lib/tavern_kit/lib/tavern_kit/prompt/middleware/trimming.rb`
  - Pre-commit: `cd lib/tavern_kit && bundle exec rake test`

---

- [ ] 14. EasyTalk Rails integration + EasyTalkCoder

  **What to do**:
  - Implement Rails 8.2 `ActiveModel::Type` integration in EasyTalk fork
  - Implement `EasyTalkCoder` for Rails `serialize` directive
  - Add `x-ui` and `x-storage` JSON Schema extension support
  - Create `ConversationSettings::Base` with nested schema support
  - Document all changes in `lib/easy_talk/FORK_CHANGES.md`

  **Must NOT do**:
  - Break existing EasyTalk functionality
  - Add any TavernKit-specific code to EasyTalk
  - Create Rails models (that's Task 15)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Deep Rails/gem integration
  - **Skills**: [`rails-tdd-minitest`, `vibe-tavern-guardrails`]
    - `rails-tdd-minitest`: TDD workflow
    - `vibe-tavern-guardrails`: Fork documentation requirements

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 11, 12, 13)
  - **Blocks**: Task 15
  - **Blocked By**: Task 3

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/playground/app/models/concerns/easy_talk_coder.rb` - Coder implementation
  - `resources/tavern_kit/playground/app/models/conversation_settings/base.rb` - Settings base
  - `resources/rails/activemodel/lib/active_model/schematized_json.rb` - Rails 8.2 type casting

  **Documentation References**:
  - `lib/easy_talk/FORK_CHANGES.md` - Document changes here (created in Task 3)

  **WHY Each Reference Matters**:
  - `easy_talk_coder.rb` shows the serialize coder pattern
  - `conversation_settings/base.rb` shows nested schema and extension support
  - `schematized_json.rb` shows type casting approach to adopt

  **Acceptance Criteria**:

  ```bash
  # EasyTalkCoder dump/load works
  bin/rails runner "
    # Define a test schema
    class TestSchema
      include EasyTalk::Model
      define_schema do
        property :name, String
        property :count, Integer
      end
    end

    coder = EasyTalkCoder.new(TestSchema)
    
    # Test dump
    schema_instance = TestSchema.new(name: 'test', count: 42)
    json = coder.dump(schema_instance)
    puts json.is_a?(String) && json.include?('test')
    
    # Test load
    loaded = coder.load('{\"name\":\"loaded\",\"count\":99}')
    puts loaded.is_a?(TestSchema)
    puts loaded.name == 'loaded'
    puts loaded.count == 99
  "
  # Assert: All 4 outputs are "true"

  # Type casting from string to integer (UI form submission scenario)
  bin/rails runner "
    class CastingSchema
      include EasyTalk::Model
      define_schema do
        property :enabled, T::Boolean
        property :limit, Integer
      end
    end

    coder = EasyTalkCoder.new(CastingSchema)
    # Simulate form params (strings)
    loaded = coder.load('{\"enabled\":\"true\",\"limit\":\"100\"}')
    puts loaded.enabled == true
    puts loaded.limit == 100
  "
  # Assert: Both outputs are "true" (strings cast to proper types)

  # Fork changes documented
  grep -c "Rails 8.2" lib/easy_talk/FORK_CHANGES.md
  # Assert: Returns >= 2

  # EasyTalk tests still pass after modifications
  cd lib/easy_talk && bundle exec rake test
  # Assert: 0 failures
  ```

  **Commit**: YES
  - Message: `feat(easy_talk): integrate with Rails 8.2 type system and add EasyTalkCoder`
  - Files: `lib/easy_talk/**/*.rb`, `app/models/concerns/easy_talk_coder.rb`
  - Pre-commit: `cd lib/easy_talk && bundle exec rake test`

---

- [ ] 15. Core Rails models (Character, Space, Preset)

  **What to do**:
  - Create `Character` model with `serialize :data, coder: EasyTalkCoder.new(TavernKit::Character::Schema)`
  - Create `Space` model (STI base for Playground/Discussion)
  - Create `Preset` model with generation and preset settings
  - Create `SpaceMembership` join model
  - Add migrations with proper jsonb columns and defaults
  - Add model validations and associations

  **Must NOT do**:
  - Implement Conversation/Message models (that's Task 16)
  - Add controller logic
  - Add frontend code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Rails model setup
  - **Skills**: [`rails-tdd-minitest`, `rails-database-migrations`, `vibe-tavern-guardrails`]
    - `rails-tdd-minitest`: Model tests
    - `rails-database-migrations`: Safe migration patterns
    - `vibe-tavern-guardrails`: Project conventions

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (depends on EasyTalk integration)
  - **Blocks**: Tasks 16, 17
  - **Blocked By**: Tasks 4, 9, 14

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/playground/app/models/character.rb` - Character model
  - `resources/tavern_kit/playground/app/models/space.rb` - Space STI base
  - `resources/tavern_kit/playground/app/models/preset.rb` - Preset model
  - `resources/tavern_kit/playground/db/migrate/20260108045602_init_schema.rb` - Migration patterns

  **Test References**:
  - `resources/tavern_kit/playground/test/models/` - Model test patterns

  **WHY Each Reference Matters**:
  - Reference models show exact serialize patterns and associations
  - Migration shows jsonb column defaults and comments
  - Tests show fixture patterns

  **STI Naming Decision** (explicit):
  - Base class: `Space` (table: `spaces`)
  - STI subclasses: `Spaces::Playground`, `Spaces::Discussion`
  - STI `type` column values: `"Spaces::Playground"`, `"Spaces::Discussion"`
  - Files: `app/models/space.rb`, `app/models/spaces/playground.rb`, `app/models/spaces/discussion.rb`

  **Acceptance Criteria**:

  ```bash
  # Migrations run
  bin/rails db:migrate:status | grep -c "up"
  # Assert: Returns number matching migration count

  # Character model works with EasyTalk serialization
  bin/rails runner "
    char = Character.create!(name: 'Test')
    puts char.persisted?
    char.reload
    puts char.data.respond_to?(:name) || char.data.is_a?(Hash)
  "
  # Assert: Both output "true"

  # Space STI works with namespaced subclasses
  bin/rails runner "
    space = Spaces::Playground.create!(name: 'Test Space', owner: User.first || User.create!(email: 'test@test.com', password: 'password'))
    puts space.is_a?(Space)
    puts space.type
    puts space.playground?
  "
  # Assert: Output is "true", "Spaces::Playground", "true"

  # Preset model works
  bin/rails runner "
    preset = Preset.create!(name: 'Test Preset')
    puts preset.persisted?
  "
  # Assert: Output is "true"
  ```

  **Fixture Prerequisites**:
  - Create `test/fixtures/users.yml` with at least one user for associations
  - Create `test/fixtures/characters.yml`, `test/fixtures/spaces.yml`, `test/fixtures/presets.yml`

  **Commit**: YES
  - Message: `feat(models): add Character, Space, Preset models with EasyTalk serialization`
  - Files: `app/models/*.rb`, `db/migrate/*.rb`, `test/models/*_test.rb`, `test/fixtures/*.yml`
  - Pre-commit: `bin/rails test test/models/`

---

### Phase 5: Integration + Frontend

- [ ] 16. Conversation/Message models

  **What to do**:
  - Create `Conversation` model (STI: root/branch/thread/checkpoint)
  - Create `Message` model with swipes support
  - Implement tree structure (`root_conversation_id`, `forked_from_message_id`)
  - Create `Conversations::VariablesStore` for atomic jsonb updates
  - Add `ConversationParticipant` join model
  - Add migrations and fixtures

  **Must NOT do**:
  - Implement conversation services (that's Task 17)
  - Add real-time features (that's Task 19)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Complex model relationships
  - **Skills**: [`rails-tdd-minitest`, `rails-database-migrations`, `vibe-tavern-guardrails`]
    - `rails-tdd-minitest`: Model tests
    - `rails-database-migrations`: Tree structure migrations
    - `vibe-tavern-guardrails`: Project conventions

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (depends on core models)
  - **Blocks**: Tasks 17, 19
  - **Blocked By**: Task 15

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/playground/app/models/conversation.rb` - Conversation model
  - `resources/tavern_kit/playground/app/models/message.rb` - Message model
  - `resources/tavern_kit/playground/app/models/conversations/variables_store.rb` - Atomic jsonb

  **Documentation References**:
  - `resources/tavern_kit/playground/AGENTS.md` - Conversation tree explanation

  **WHY Each Reference Matters**:
  - `conversation.rb` shows STI setup and tree structure
  - `message.rb` shows swipes implementation
  - `variables_store.rb` shows atomic jsonb_set pattern for macro variables

  **Acceptance Criteria**:

  ```bash
  # Conversation tree works
  bin/rails runner "
    root = Conversation.create!(space: spaces(:one))
    branch = root.branches.create!(space: spaces(:one))
    puts branch.root_conversation == root
  "
  # Assert: Output is "true"

  # Message swipes work
  bin/rails runner "
    msg = Message.create!(conversation: conversations(:one), role: 'assistant', content: 'Hello')
    swipe = msg.swipes.create!(content: 'Hi there')
    puts msg.swipes.count
  "
  # Assert: Output is "1"
  ```

  **Commit**: YES
  - Message: `feat(models): add Conversation and Message models with tree structure`
  - Files: `app/models/conversation.rb`, `app/models/message.rb`, `app/models/conversations/*.rb`, `db/migrate/*.rb`
  - Pre-commit: `bin/rails test test/models/`

---

- [ ] 17. PromptBuilder service with adapters

  **What to do**:
  - Create `PromptBuilder` service as main entry point
  - Create adapters in `app/services/prompt_building/`:
    - `CharacterAdapter` - Convert Character model to TavernKit::Character
    - `ParticipantAdapter` - Convert User/Character to Participant
    - `PresetResolver` - Resolve preset from various sources
    - `CharacterParticipantBuilder` - Build participant from character
  - Integrate with TavernKit gem DSL
  - Return `TavernKit::Prompt::Plan`

  **Must NOT do**:
  - Implement LLM client calls
  - Add streaming logic (that's Task 19)
  - Implement conversation executor (too complex for initial)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Service layer integration
  - **Skills**: [`rails-tdd-minitest`, `vibe-tavern-guardrails`]
    - `rails-tdd-minitest`: Service tests
    - `vibe-tavern-guardrails`: Adapter patterns

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (depends on models + dialects)
  - **Blocks**: Tasks 18, 19
  - **Blocked By**: Tasks 10, 15, 16

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/playground/app/services/prompt_builder.rb` - Main service
  - `resources/tavern_kit/playground/app/services/prompt_building/character_adapter.rb` - Character adapter
  - `resources/tavern_kit/playground/app/services/prompt_building/participant_adapter.rb` - Participant adapter

  **Test References**:
  - `resources/tavern_kit/playground/test/services/prompt_builder_test.rb` - Service tests

  **WHY Each Reference Matters**:
  - `prompt_builder.rb` shows the integration pattern with TavernKit DSL
  - Adapters show how to convert ActiveRecord models to gem domain objects
  - Tests show how to verify prompt output

  **Acceptance Criteria**:

  **Fixture Prerequisites**: 
  - `test/fixtures/conversations.yml` with `:one` conversation (from Task 16)
  - `test/fixtures/characters.yml` with `:one` character (from Task 15)

  ```bash
  # PromptBuilder produces plan
  bin/rails runner "
    # Use fixture via direct load for acceptance test
    conversation = Conversation.first || Conversation.create!(space: Space.first)
    builder = PromptBuilder.new(conversation)
    plan = builder.build
    puts plan.is_a?(TavernKit::Prompt::Plan)
    puts plan.blocks.size > 0
  "
  # Assert: Both output "true"

  # Adapters convert correctly
  bin/rails runner "
    char = Character.first || Character.create!(name: 'Test')
    adapted = PromptBuilding::CharacterAdapter.call(char)
    puts adapted.is_a?(TavernKit::Character)
  "
  # Assert: Output is "true"
  ```

  **Commit**: YES
  - Message: `feat(services): add PromptBuilder service with adapters`
  - Files: `app/services/prompt_builder.rb`, `app/services/prompt_building/*.rb`, `test/services/**/*_test.rb`
  - Pre-commit: `bin/rails test test/services/`

---

- [ ] 18. API controllers

  **What to do**:
  - Create `Api::CharactersController` (CRUD + import/export)
  - Create `Api::SpacesController` (CRUD)
  - Create `Api::PresetsController` (CRUD)
  - Create `Api::ConversationsController` (CRUD + branch/fork)
  - Create `Api::MessagesController` (CRUD + swipes)
  - Add routes under `/api/v1/`
  - Add request tests

  **Must NOT do**:
  - Implement streaming endpoints (that's Task 19)
  - Add authentication (out of scope for initial)
  - Add rate limiting

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Standard Rails controllers
  - **Skills**: [`rails-tdd-minitest`, `vibe-tavern-guardrails`]
    - `rails-tdd-minitest`: Controller/integration tests
    - `vibe-tavern-guardrails`: API patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 19, 20)
  - **Blocks**: None
  - **Blocked By**: Task 17

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/playground/app/controllers/characters_controller.rb` - Character CRUD pattern
  - `resources/tavern_kit/playground/app/controllers/conversations_controller.rb` - Conversation patterns
  - `resources/tavern_kit/playground/app/controllers/presets_controller.rb` - Preset patterns
  - `resources/tavern_kit/playground/config/routes.rb` - Route patterns (note: reference uses web controllers, not API namespace)

  **Design Decision** (explicit):
  - Create new `Api::V1::*` namespaced controllers (not in reference)
  - Use consistent JSON response format:
    - Collections: `{ "characters": [...], "meta": { "total": N } }`
    - Singles: `{ "character": {...} }` (resource name as root key)
    - Errors: `{ "error": "message", "errors": ["detail1", "detail2"] }`
    - Status codes: 200 (success), 201 (created), 204 (deleted), 400 (bad request), 404 (not found), 422 (validation failed)

  **API Endpoints to Implement**:
  ```
  GET    /api/v1/characters          # List characters
  POST   /api/v1/characters          # Create character (JSON or PNG upload)
  GET    /api/v1/characters/:id      # Show character
  PATCH  /api/v1/characters/:id      # Update character
  DELETE /api/v1/characters/:id      # Delete character
  GET    /api/v1/characters/:id/export # Export as JSON or PNG

  GET    /api/v1/spaces              # List spaces
  POST   /api/v1/spaces              # Create space
  GET    /api/v1/spaces/:id          # Show space
  PATCH  /api/v1/spaces/:id          # Update space
  DELETE /api/v1/spaces/:id          # Delete space

  GET    /api/v1/presets             # List presets
  POST   /api/v1/presets             # Create preset
  GET    /api/v1/presets/:id         # Show preset
  PATCH  /api/v1/presets/:id         # Update preset
  DELETE /api/v1/presets/:id         # Delete preset

  GET    /api/v1/conversations       # List conversations (within space)
  POST   /api/v1/conversations       # Create conversation
  GET    /api/v1/conversations/:id   # Show conversation with messages
  DELETE /api/v1/conversations/:id   # Delete conversation
  POST   /api/v1/conversations/:id/fork # Fork conversation from message

  GET    /api/v1/conversations/:conversation_id/messages  # List messages
  POST   /api/v1/conversations/:conversation_id/messages  # Create message
  DELETE /api/v1/messages/:id        # Delete message
  ```

  **WHY Each Reference Matters**:
  - Web controllers show authorization patterns and model interactions
  - Routes show resource nesting and custom actions
  - Note: We're creating API controllers from scratch since reference doesn't have them

  **Acceptance Criteria**:

  **Example Response Payloads**:
  ```json
  // GET /api/v1/characters (list)
  { "characters": [{"id": 1, "name": "Alice"}, ...], "meta": {"total": 10} }

  // GET /api/v1/characters/1 (show)
  { "character": {"id": 1, "name": "Alice", "data": {...}} }

  // POST /api/v1/characters (create - success)
  { "character": {"id": 2, "name": "Bob"} }  // status 201

  // POST /api/v1/characters (validation error)
  { "error": "Validation failed", "errors": ["Name can't be blank"] }  // status 422

  // DELETE /api/v1/characters/1
  // status 204 (no body)
  ```

  ```bash
  # Characters API - list returns array under "characters" key
  curl -s http://localhost:3000/api/v1/characters | jq '.characters | type'
  # Assert: Output is "array"

  # Characters API - show returns object under "character" key
  curl -s http://localhost:3000/api/v1/characters/1 | jq '.character.name'
  # Assert: Output is a string (character name)

  # Controller tests pass
  bin/rails test test/controllers/api/
  # Assert: 0 failures
  ```

  **Commit**: YES
  - Message: `feat(api): add API controllers for characters, spaces, presets, conversations`
  - Files: `app/controllers/api/**/*.rb`, `config/routes.rb`, `test/controllers/api/**/*_test.rb`
  - Pre-commit: `bin/rails test test/controllers/`

---

- [ ] 19. ActionCable streaming

  **What to do**:
  - Create `ConversationChannel` for real-time updates
  - Implement ephemeral typing indicator (no placeholder messages)
  - Implement message streaming via ActionCable
  - Create `Conversations::RunExecutor` service for LLM interaction
  - Use Turbo Streams for persistent DOM updates
  - Handle connection/disconnection gracefully

  **Must NOT do**:
  - Implement actual LLM client (use mock/stub)
  - Add auto-reply features (Phase 5+)
  - Implement group chat turn scheduling

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Real-time architecture
  - **Skills**: [`rails-tdd-minitest`, `vibe-tavern-guardrails`]
    - `rails-tdd-minitest`: Channel tests
    - `vibe-tavern-guardrails`: No-placeholder pattern

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 18, 20)
  - **Blocks**: Task 20
  - **Blocked By**: Tasks 16, 17

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/playground/app/channels/conversation_channel.rb` - Channel implementation
  - `resources/tavern_kit/playground/app/services/conversations/run_executor.rb` - LLM execution

  **Documentation References**:
  - `resources/tavern_kit/playground/AGENTS.md` - "No placeholder message" pattern explanation

  **WHY Each Reference Matters**:
  - `conversation_channel.rb` shows subscription and broadcast patterns
  - `run_executor.rb` shows streaming integration with ActionCable
  - AGENTS.md explains the ephemeral typing indicator approach

  **Acceptance Criteria**:

  ```bash
  # Channel exists
  bin/rails runner "puts defined?(ConversationChannel)"
  # Assert: Output is "constant"

  # Cable config exists
  cat config/cable.yml | grep -c "adapter"
  # Assert: Returns >= 1

  # Using playwright skill for streaming test:
  # 1. Navigate to /conversations/1
  # 2. Send message "Hello"
  # 3. Wait for typing indicator to appear
  # 4. Wait for response message to appear
  # 5. Assert: Response message contains text
  ```

  **Commit**: YES
  - Message: `feat(channels): add ActionCable streaming for conversations`
  - Files: `app/channels/*.rb`, `app/services/conversations/run_executor.rb`, `config/cable.yml`
  - Pre-commit: `bin/rails test test/channels/`

---

- [ ] 20. Stimulus controllers for chat UI

  **What to do**:
  - Create `chat_controller.js` for message input and submission
  - Create `message_controller.js` for individual message interactions
  - Create `typing_indicator_controller.js` for ephemeral typing state
  - Create basic chat view templates
  - Wire up Turbo Streams for message updates
  - Add basic CSS styling (Tailwind)

  **Must NOT do**:
  - Implement character card import UI (Phase 5+)
  - Implement settings management UI
  - Add complex animations

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Frontend UI work
  - **Skills**: [`rails-tdd-minitest`, `frontend-ui-ux`]
    - `rails-tdd-minitest`: System tests
    - `frontend-ui-ux`: UI/UX patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 18)
  - **Blocks**: None
  - **Blocked By**: Task 19

  **References**:

  **Pattern References**:
  - `resources/tavern_kit/playground/app/javascript/controllers/` - Stimulus controllers
  - `resources/tavern_kit/playground/app/views/conversations/` - View templates

  **Documentation References**:
  - `AGENTS.md` - Frontend asset patterns (Bun + Tailwind)

  **WHY Each Reference Matters**:
  - Reference controllers show Stimulus patterns for chat
  - View templates show Turbo Stream integration

  **Acceptance Criteria**:

  ```bash
  # JavaScript builds
  bun run build
  # Assert: Exit code 0

  # Controllers exist
  ls app/javascript/controllers/*.js | wc -l
  # Assert: Returns >= 3

  # Using playwright skill for UI test:
  # 1. Navigate to /conversations/1
  # 2. Type "Hello" in input
  # 3. Click send button
  # 4. Wait for message to appear in chat
  # 5. Assert: Message with "Hello" is visible
  ```

  **Commit**: YES
  - Message: `feat(frontend): add Stimulus controllers and chat UI`
  - Files: `app/javascript/controllers/*.js`, `app/views/conversations/*.html.erb`, `app/assets/stylesheets/*.css`
  - Pre-commit: `bun run lint && bin/rails test:system`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `test(tavern_kit): port reference test suite` | `lib/tavern_kit/test/**/*` | Tests load |
| 2 | `feat(tavern_kit): add error hierarchy and core models` | `lib/tavern_kit/lib/**/*.rb` | `bundle exec rake test` |
| 3 | `docs(easy_talk): document fork changes` | `lib/easy_talk/FORK_CHANGES.md` | File exists |
| 4 | `feat(tavern_kit): implement Character Card V2/V3` | `lib/tavern_kit/lib/**/character_card*.rb` | `bundle exec rake test` |
| 5 | `feat(tavern_kit): implement PNG parser/writer` | `lib/tavern_kit/lib/**/png/*.rb` | `bundle exec rake test` |
| 6 | `feat(tavern_kit): implement basic macro system` | `lib/tavern_kit/lib/**/macro/**/*.rb` | `bundle exec rake test` |
| 7 | `feat(tavern_kit): implement middleware pipeline` | `lib/tavern_kit/lib/**/prompt/pipeline.rb` | `bundle exec rake test` |
| 8 | `feat(tavern_kit): implement core middleware` | `lib/tavern_kit/lib/**/prompt/middleware/*.rb` | `bundle exec rake test` |
| 9 | `feat(tavern_kit): implement Preset and PromptEntry` | `lib/tavern_kit/lib/**/preset.rb` | `bundle exec rake test` |
| 10 | `feat(tavern_kit): implement output dialects` | `lib/tavern_kit/lib/**/dialects/*.rb` | `bundle exec rake test` |
| 11 | `feat(tavern_kit): implement full macro pack` | `lib/tavern_kit/lib/**/macro/packs/*.rb` | `bundle exec rake test` |
| 12 | `feat(tavern_kit): implement World Info engine` | `lib/tavern_kit/lib/**/lore/*.rb` | `bundle exec rake test` |
| 13 | `feat(tavern_kit): implement context trimming` | `lib/tavern_kit/lib/**/trimmer.rb` | `bundle exec rake test` |
| 14 | `feat(easy_talk): add Rails 8.2 integration` | `lib/easy_talk/**/*.rb`, `app/models/concerns/*.rb` | `bin/ci` |
| 15 | `feat(models): add core Rails models` | `app/models/*.rb`, `db/migrate/*.rb` | `bin/rails test test/models/` |
| 16 | `feat(models): add Conversation/Message models` | `app/models/conversation.rb`, `app/models/message.rb` | `bin/rails test test/models/` |
| 17 | `feat(services): add PromptBuilder with adapters` | `app/services/**/*.rb` | `bin/rails test test/services/` |
| 18 | `feat(api): add API controllers` | `app/controllers/api/**/*.rb` | `bin/rails test test/controllers/` |
| 19 | `feat(channels): add ActionCable streaming` | `app/channels/*.rb` | `bin/rails test test/channels/` |
| 20 | `feat(frontend): add chat UI` | `app/javascript/**/*.js`, `app/views/**/*.erb` | `bin/rails test:system` |

---

## Success Criteria

### Verification Commands
```bash
# Gem tests pass
cd lib/tavern_kit && bundle exec rake test
# Expected: 0 failures, 0 errors

# Full CI passes
bin/ci
# Expected: Exit code 0

# Character card round-trip
bin/rails runner "
  card = TavernKit::CharacterCard.load('test/fixtures/files/seraphina.png')
  v2 = TavernKit::CharacterCard.export_v2(card)
  roundtrip = TavernKit::CharacterCard.load(v2)
  puts roundtrip.name == card.name ? 'PASS' : 'FAIL'
"
# Expected: PASS

# Prompt build works
bin/rails runner "
  plan = PromptBuilder.new(conversations(:one)).build
  msgs = plan.to_messages(dialect: :openai)
  puts msgs.size > 0 ? 'PASS' : 'FAIL'
"
# Expected: PASS
```

### Parity Harness (Prompt Output Verification)

To verify "Prompt output matches reference implementation for same inputs":

```bash
# 1. Create identical test inputs in both implementations
# Reference: resources/tavern_kit/test/fixtures/
# New: lib/tavern_kit/test/fixtures/

# 2. Run reference implementation
cd resources/tavern_kit && ruby -e "
  require_relative 'lib/tavern_kit'
  card = TavernKit::CharacterCard.load('test/fixtures/seraphina.json')
  user = TavernKit::User.new(name: 'Alex')
  plan = TavernKit.build(character: card, user: user, message: 'Hello')
  puts plan.to_messages(dialect: :openai).to_json
" > /tmp/reference_output.json

# 3. Run new implementation
cd lib/tavern_kit && ruby -e "
  require_relative 'lib/tavern_kit'
  card = TavernKit::CharacterCard.load('test/fixtures/seraphina.json')
  user = TavernKit::User.new(name: 'Alex')
  plan = TavernKit.build(character: card, user: user, message: 'Hello')
  puts plan.to_messages(dialect: :openai).to_json
" > /tmp/new_output.json

# 4. Compare (normalize JSON for comparison)
jq -S . /tmp/reference_output.json > /tmp/ref_sorted.json
jq -S . /tmp/new_output.json > /tmp/new_sorted.json
diff /tmp/ref_sorted.json /tmp/new_sorted.json
# Assert: No differences (exit code 0)
```

**Equivalence criteria**: Exact JSON match after sorting keys. If outputs differ only in non-semantic ways (whitespace, key order), they are considered equivalent.

---

### Final Checklist
- [ ] All gem tests pass (`cd lib/tavern_kit && bundle exec rake test`)
- [ ] All Rails tests pass (`bin/rails test`)
- [ ] CI passes (`bin/ci`)
- [ ] Character Card V2/V3 round-trip preserves data
- [ ] Macros expand correctly (50+ ST-compatible)
- [ ] World Info activates on keywords
- [ ] Context trimming respects budget
- [ ] Output dialects format correctly
- [ ] Real-time streaming works end-to-end
- [ ] No Rails dependencies in gem (`lib/tavern_kit/`)
