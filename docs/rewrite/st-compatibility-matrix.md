# SillyTavern Compatibility Matrix

Reference: SillyTavern v1.15.0
TavernKit Layer: `TavernKit::SillyTavern`

NOTE (2026-01-31): This matrix is currently stale (it was written before the
Wave 3/4 implementation landed). Many items below marked as "not started" are
now implemented. Use `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md` and
`docs/rewrite/wave4-contracts.md` as the current source of truth. We will
refresh this matrix in Wave 6.

This matrix tracks TavernKit's implementation status against SillyTavern v1.15.0
features. Use this document both as:
1. **Behavior documentation** - understanding ST/TavernKit differences
2. **Implementation TODO list** - tracking feature completion

Status legend:
- ✅ Implemented
- 🔨 In progress
- ❌ Not started
- ⏸️ Deferred
- 🚫 Intentional divergence

---

## 1. Character Card Support

### 1.1 CCv2 / CCv3 Core Fields

| Field | CCv2 | CCv3 | TavernKit | Wave |
|-------|------|------|-----------|------|
| `spec` / `spec_version` | ✅ | ✅ | ✅ | 1 |
| `data` wrapper | ✅ | ✅ | ✅ | 1 |
| `name` | ✅ | ✅ | ✅ | 1 |
| `description` | ✅ | ✅ | ✅ | 1 |
| `personality` | ✅ | ✅ | ✅ | 1 |
| `scenario` | ✅ | ✅ | ✅ | 1 |
| `first_mes` | ✅ | ✅ | ✅ | 1 |
| `mes_example` | ✅ | ✅ | ✅ | 1 |
| `alternate_greetings` | ✅ | ✅ | ✅ | 1 |
| `system_prompt` | ✅ | ✅ | ✅ | 1 |
| `post_history_instructions` | ✅ | ✅ | ✅ | 1 |
| `creator_notes` | ✅ | ✅ | ✅ | 1 |
| `character_book` | ✅ | ✅ | ✅ | 1 |
| `tags` | ✅ | ✅ | ✅ | 1 |
| `creator` | ✅ | ✅ | ✅ | 1 |
| `character_version` | ✅ | ✅ | ✅ | 1 |
| `extensions` (preserve unknown) | ✅ | ✅ | ✅ | 1 |
| `group_only_greetings` | ❌ | ✅ | ✅ | 1 |
| `assets` | ❌ | ✅ | ✅ | 1 |
| `nickname` | ❌ | ✅ | ✅ | 1 |
| `creator_notes_multilingual` | ❌ | ✅ | ✅ | 1 |
| `source` | ❌ | ✅ | ✅ | 1 |
| `creation_date` | ❌ | ✅ | ✅ | 1 |
| `modification_date` | ❌ | ✅ | ✅ | 1 |

### 1.2 ST `data.extensions` Keys

| Key | ST | TavernKit | Notes |
|-----|-----|-----------|-------|
| `talkativeness` | ✅ | ✅ | Group chat activation probability |
| `world` | ✅ | ✅ | Linked World Info name |
| `depth_prompt` | ✅ | ✅ | Character Depth Prompt config |
| `fav` | ✅ | 🚫 | UI-only; preserved but not interpreted |

---

## 2. Macro System

### 2.1 Engines

| Engine | ST | TavernKit | Wave |
|--------|-----|-----------|------|
| Legacy substitution (`substituteParamsLegacy`) | ✅ | ❌ | 3 |
| V2 Engine (`MacroEngine`) | ✅ | ❌ | 3 |

### 2.2 V2 Engine Features

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| True macro nesting (`{{outer::{{inner}}}}`) | ✅ | ❌ | 3 |
| Depth-first evaluation | ✅ | ❌ | 3 |
| Unknown macros preserved | ✅ | ❌ | 3 |
| Scoped block macros (`{{macro}}...{{/macro}}`) | ✅ | ❌ | 3 |
| `{{if}}`/`{{else}}` conditional | ✅ | ❌ | 3 |
| Variable shorthand (`{{.var}}`, `{{$var}}`) | ✅ | ❌ | 3 |
| 16 variable operators | ✅ | ❌ | 3 |
| Macro flags (6 types: `!?~>/#`) | ✅ | ❌ | 3 |
| Typed argument validation | ✅ | ❌ | 3 |
| Pre/post-processor pipeline | ✅ | ❌ | 3 |
| `{{pick}}` deterministic seeding (4 components) | ✅ | ❌ | 3 |
| Auto-trim/dedent scoped content | ✅ | ❌ | 3 |
| `#` flag (preserve whitespace) | ✅ | ❌ | 3 |
| `/` flag (closing block) | ✅ | ❌ | 3 |

### 2.3 Built-in Macros (~81 total)

| Category | Count | ST | TavernKit | Wave |
|----------|-------|-----|-----------|------|
| UTILITY | 10 | ✅ | ❌ | 3 |
| RANDOM | 3 | ✅ | ❌ | 3 |
| NAMES | 5 | ✅ | ❌ | 3 |
| CHARACTER | 11 | ✅ | ❌ | 3 |
| CHAT | 8 | ✅ | ❌ | 3 |
| TIME | 8 | ✅ | ❌ | 3 |
| VARIABLE | 14 | ✅ | ❌ | 3 |
| PROMPTS (instruct) | 19 | ✅ | ❌ | 3 |
| STATE | 3 | ✅ | ❌ | 3 |

#### Key Macros Detail

| Macro | ST | TavernKit | Notes |
|-------|-----|-----------|-------|
| `{{char}}` / `{{user}}` | ✅ | ❌ | Basic names |
| `{{description}}` / `{{personality}}` / `{{scenario}}` | ✅ | ❌ | Character data |
| `{{mesExamples}}` / `{{mesExamplesRaw}}` | ✅ | ❌ | Example messages |
| `{{charPrompt}}` / `{{charJailbreak}}` | ✅ | ❌ | Character overrides |
| `{{original}}` | ✅ | ❌ | Splice global default |
| `{{lastMessage}}` / `{{lastUserMessage}}` / `{{lastCharMessage}}` | ✅ | ❌ | Chat history |
| `{{date}}` / `{{time}}` / `{{weekday}}` | ✅ | ❌ | Date/time |
| `{{random::a,b,c}}` / `{{pick::a,b,c}}` / `{{roll:dN}}` | ✅ | ❌ | Randomization |
| `{{setvar}}` / `{{getvar}}` / `{{incvar}}` / `{{decvar}}` | ✅ | ❌ | Variables |
| `{{hasvar}}` / `{{deletevar}}` | ✅ | ❌ | Variable existence/deletion |
| `{{setglobalvar}}` / `{{getglobalvar}}` | ✅ | ❌ | Global variables |
| `{{hasglobalvar}}` / `{{deleteglobalvar}}` | ✅ | ❌ | Global var exists/delete |
| `{{if condition}}...{{else}}...{{/if}}` | ✅ | ❌ | Conditionals |
| `{{space}}` / `{{space::N}}` | ✅ | ❌ | Whitespace |
| `{{newline}}` / `{{newline::N}}` | ✅ | ❌ | Newlines |
| `{{trim}}` | ✅ | ❌ | Trim whitespace |
| `{{noop}}` | ✅ | ❌ | No operation |
| `{{banned "..."}}` | ✅ | ❌ | Stopping strings |
| `{{group}}` / `{{groupNotMuted}}` / `{{notChar}}` | ✅ | ❌ | Group macros |
| `{{hasExtension}}` | ✅ | ❌ | Extension check via Macro::Environment `extensions` surface |
| `<USER>` / `<BOT>` / `<CHAR>` | ✅ | ❌ | Legacy angle-bracket aliases (pre-processor normalization) |

---

## 3. World Info / Lorebook

### 3.1 Core Features

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| Keyword matching | ✅ | ❌ | 3 |
| Secondary keys (selective) | ✅ | ❌ | 3 |
| Regex keys (JS) | ✅ | ❌ | 3 |
| `match_whole_words` | ✅ | ❌ | 3 |
| `case_sensitive` | ✅ | ❌ | 3 |
| Constant entries | ✅ | ❌ | 3 |
| Token budget | ✅ | ❌ | 3 |
| Recursive scanning | ✅ | ❌ | 3 |
| `scan_depth` (0=none) | ✅ | ❌ | 3 |
| Insertion strategies | ✅ | ❌ | 3 |
| Min activations depth skew | ✅ | ❌ | 3 |
| Timed effects (sticky/cooldown/delay) | ✅ | ❌ | 3 |
| Probability | ✅ | ❌ | 3 |
| `useProbability` toggle | ✅ | ❌ | 3 |

### 3.2 Entry Positions (8 types)

| Position | ST | TavernKit | Wave |
|----------|-----|-----------|------|
| `before_char_defs` | ✅ | ❌ | 3 |
| `after_char_defs` | ✅ | ❌ | 3 |
| `before_example_messages` | ✅ | ❌ | 3 |
| `after_example_messages` | ✅ | ❌ | 3 |
| `top_of_an` | ✅ | ❌ | 3 |
| `bottom_of_an` | ✅ | ❌ | 3 |
| `at_depth` (in-chat) | ✅ | ❌ | 3 |
| `outlet` | ✅ | ❌ | 3 |

### 3.3 Entry Fields (40+ total)

| Field | ST | TavernKit | Notes |
|-------|-----|-----------|-------|
| `keys` / `secondary_keys` | ✅ | ❌ | Keywords |
| `content` | ✅ | ❌ | Entry text |
| `enabled` / `constant` | ✅ | ❌ | Activation |
| `position` / `depth` / `order` | ✅ | ❌ | Placement |
| `priority` / `selectiveLogic` | ✅ | ❌ | Logic |
| `matchPersonaDescription` | ✅ | ❌ | Non-chat scan opt-in |
| `matchCharacterDescription` | ✅ | ❌ | Non-chat scan opt-in |
| `matchCharacterPersonality` | ✅ | ❌ | Non-chat scan opt-in |
| `matchCharacterDepthPrompt` | ✅ | ❌ | Non-chat scan opt-in |
| `matchScenario` | ✅ | ❌ | Non-chat scan opt-in |
| `matchCreatorNotes` | ✅ | ❌ | Non-chat scan opt-in |
| `characterFilter.names[]` | ✅ | ❌ | Character filter |
| `characterFilter.tags[]` | ✅ | ❌ | Tag filter |
| `characterFilter.isExclude` | ✅ | ❌ | Invert filter |
| `triggers[]` | ✅ | ❌ | Generation type filter |
| `groupOverride` / `groupWeight` | ✅ | ❌ | Group scoring |
| `sticky` / `cooldown` / `delay` | ✅ | ❌ | Timed effects |
| `ignoreBudget` | ✅ | ❌ | Bypass budget |
| `preventRecursion` / `delayUntilRecursion` | ✅ | ❌ | Recursion control |

### 3.4 Decorators

| Decorator | ST | TavernKit | Wave |
|-----------|-----|-----------|------|
| `@@activate` | ✅ | ❌ | 3 |
| `@@dont_activate` | ✅ | ❌ | 3 |

### 3.5 Advanced Features

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| Inclusion groups | ✅ | ❌ | 3 |
| Group scoring | ✅ | ❌ | 3 |
| Forced activations | ✅ | ❌ | 3 |
| Per-entry scan depth override | ✅ | ❌ | 3 |
| `automationId` | ✅ | ⏸️ | Parsed, not used |

### 3.6 Callback Interfaces

| Callback | ST Event | TavernKit | Wave |
|----------|----------|-----------|------|
| `force_activate` | `WORLDINFO_FORCE_ACTIVATE` | ❌ | 3 |
| `on_scan_done` | `WORLDINFO_SCAN_DONE` | ❌ | 3 |
| `on_entries_loaded` | `WORLDINFO_ENTRIES_LOADED` | ⏸️ | Deferred |
| `on_activated` | `WORLD_INFO_ACTIVATED` | ⏸️ | Deferred |

### 3.7 Import Formats

| Format | ST | TavernKit | Notes |
|--------|-----|-----------|-------|
| ST native JSON | ✅ | ❌ | Primary |
| Character Book (CCv2/CCv3) | ✅ | ✅ | Embedded in cards |
| Novel AI | ✅ | ⏸️ | Low priority |
| Agnai | ✅ | ⏸️ | Low priority |
| RisuAI | ✅ | ⏸️ | Low priority |

---

## 4. Prompt Manager

### 4.1 Core Features

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| `prompt_entries` array | ✅ | ❌ | 4 |
| Entry normalization (FORCE_RELATIVE_IDS) | ✅ | ❌ | 4 |
| Entry normalization (FORCE_LAST_IDS) | ✅ | ❌ | 4 |
| In-chat injection (depth semantics) | ✅ | ❌ | 4 |
| Same depth ordering (by `order` asc) | ✅ | ❌ | 4 |
| Role ordering (Assistant > User > System) | ✅ | ❌ | 4 |
| Same depth+order+role merging | ✅ | ❌ | 4 |
| `{{original}}` splicing | ✅ | ❌ | 3 |
| `prefer_char_prompt` | ✅ | ❌ | 4 |
| `prefer_char_instructions` | ✅ | ❌ | 4 |
| `forbid_overrides` | ✅ | ❌ | 4 |

### 4.2 Pinned Groups (14 slots)

| Slot | ST | TavernKit | Wave |
|------|-----|-----------|------|
| `main_prompt` | ✅ | ❌ | 4 |
| `persona_description` | ✅ | ❌ | 4 |
| `character_description` | ✅ | ❌ | 4 |
| `character_personality` | ✅ | ❌ | 4 |
| `scenario` | ✅ | ❌ | 4 |
| `chat_examples` | ✅ | ❌ | 4 |
| `chat_history` | ✅ | ❌ | 4 |
| `authors_note` | ✅ | ❌ | 4 |
| `wi_before` / `wi_after` | ✅ | ❌ | 4 |
| `jailbreak` | ✅ | ❌ | 4 |
| ... (more) | ✅ | ❌ | 4 |

---

## 5. Preset / Configuration

### 5.1 Sampling Parameters

| Field | ST | TavernKit | Wave |
|-------|-----|-----------|------|
| `temp_openai` | ✅ | ❌ | 2 |
| `top_p_openai` | ✅ | ❌ | 2 |
| `top_k_openai` | ✅ | ❌ | 2 |
| `freq_pen_openai` | ✅ | ❌ | 2 |
| `pres_pen_openai` | ✅ | ❌ | 2 |

### 5.2 Token Budget

| Field | ST | TavernKit | Wave |
|-------|-----|-----------|------|
| `openai_max_context` | ✅ | ❌ | 2 |
| `openai_max_tokens` | ✅ | ❌ | 2 |
| `max_context_unlocked` | ✅ | ❌ | 2 |

### 5.3 Template Prompts

| Field | ST | TavernKit | Wave |
|-------|-----|-----------|------|
| `send_if_empty` | ✅ | ❌ | 2 |
| `impersonation_prompt` | ✅ | ❌ | 2 |
| `new_chat_prompt` | ✅ | ❌ | 2 |
| `new_group_chat_prompt` | ✅ | ❌ | 2 |
| `new_example_chat_prompt` | ✅ | ❌ | 2 |
| `continue_nudge_prompt` | ✅ | ❌ | 2 |
| `group_nudge_prompt` | ✅ | ❌ | 2 |
| `assistant_prefill` | ✅ | ❌ | 2 |
| `assistant_impersonation` | ✅ | ❌ | 2 |

### 5.4 Format Templates

| Field | ST | TavernKit | Wave |
|-------|-----|-----------|------|
| `wi_format` | ✅ | ❌ | 2 |
| `scenario_format` | ✅ | ❌ | 2 |
| `personality_format` | ✅ | ❌ | 2 |

---

## 6. Instruct Mode

### 6.1 Sequences (24 attributes)

| Attribute | ST | TavernKit | Wave |
|-----------|-----|-----------|------|
| `input_sequence` | ✅ | ❌ | 2 |
| `output_sequence` | ✅ | ❌ | 2 |
| `system_sequence` | ✅ | ❌ | 2 |
| `stop_sequence` | ✅ | ❌ | 2 |
| `first_input_sequence` | ✅ | ❌ | 2 |
| `last_input_sequence` | ✅ | ❌ | 2 |
| `first_output_sequence` | ✅ | ❌ | 2 |
| `last_output_sequence` | ✅ | ❌ | 2 |
| `story_string_prefix` | ✅ | ❌ | 2 |
| `story_string_suffix` | ✅ | ❌ | 2 |
| ... (14 more) | ✅ | ❌ | 2 |

### 6.2 Instruct Macros (19 total)

| Macro | ST | TavernKit | Wave |
|-------|-----|-----------|------|
| `{{instructUserPrefix}}` | ✅ | ❌ | 4 |
| `{{instructAssistantPrefix}}` | ✅ | ❌ | 4 |
| `{{instructSystemPrefix}}` | ✅ | ❌ | 4 |
| `{{instructStop}}` | ✅ | ❌ | 4 |
| `{{defaultSystemPrompt}}` | ✅ | ❌ | 4 |
| `{{systemPrompt}}` | ✅ | ❌ | 4 |
| ... (13 more) | ✅ | ❌ | 4 |

### 6.3 Names Behavior

| Mode | ST | TavernKit | Wave |
|------|-----|-----------|------|
| `NONE` | ✅ | ❌ | 2 |
| `FORCE` | ✅ | ❌ | 2 |
| `ALWAYS` | ✅ | ❌ | 2 |

---

## 7. Context Template

### 7.1 Story String (Handlebars)

| Placeholder | ST | TavernKit | Wave |
|-------------|-----|-----------|------|
| `{{system}}` | ✅ | ❌ | 2 |
| `{{description}}` | ✅ | ❌ | 2 |
| `{{personality}}` | ✅ | ❌ | 2 |
| `{{scenario}}` | ✅ | ❌ | 2 |
| `{{persona}}` | ✅ | ❌ | 2 |
| `{{char}}` | ✅ | ❌ | 2 |
| `{{wiBefore}}` / `{{wiAfter}}` | ✅ | ❌ | 2 |
| `{{anchorBefore}}` / `{{anchorAfter}}` | ✅ | ❌ | 2 |

### 7.2 Context Template Fields

| Field | ST | TavernKit | Wave |
|-------|-----|-----------|------|
| `story_string` | ✅ | ❌ | 2 |
| `chat_start` | ✅ | ❌ | 2 |
| `example_separator` | ✅ | ❌ | 2 |
| `story_string_position` | ✅ | ❌ | 2 |
| `story_string_depth` | ✅ | ❌ | 2 |
| `story_string_role` | ✅ | ❌ | 2 |
| `use_stop_strings` | ✅ | ❌ | 2 |

---

## 8. Persona Description

### 8.1 Positions (5 types)

| Position | ST | TavernKit | Wave |
|----------|-----|-----------|------|
| `IN_PROMPT (0)` | ✅ | ❌ | 4 |
| `AFTER_CHAR (1)` | ✅ | 🚫 | Deprecated |
| `TOP_AN (2)` | ✅ | ❌ | 4 |
| `BOTTOM_AN (3)` | ✅ | ❌ | 4 |
| `AT_DEPTH (4)` | ✅ | ❌ | 4 |
| `NONE (9)` | ✅ | ❌ | 4 |

---

## 9. Author's Note

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| In-chat @ depth | ✅ | ❌ | 4 |
| Interval-based insertion | ✅ | ❌ | 4 |
| Character-specific notes | ✅ | ❌ | 4 |
| Position: replace/before/after | ✅ | ❌ | 4 |
| Macro expansion | ✅ | ❌ | 4 |

---

## 10. Extension Prompts

### 10.1 Injection Types

| Type | ST | TavernKit | Wave |
|------|-----|-----------|------|
| `NONE (-1)` | ✅ | ❌ | 4 |
| `IN_PROMPT (0)` | ✅ | ❌ | 4 |
| `IN_CHAT (1)` | ✅ | ❌ | 4 |
| `BEFORE_PROMPT (2)` | ✅ | ❌ | 4 |

### 10.2 Built-in Extension IDs

| ID | ST | TavernKit | Notes |
|----|-----|-----------|-------|
| `1_memory` | ✅ | ❌ | Memory/Summarize |
| `2_floating_prompt` | ✅ | ❌ | Author's Note |
| `3_vectors` | ✅ | ❌ | Vectors/RAG |
| `4_vectors_data_bank` | ✅ | ❌ | Data Bank |
| `PERSONA_DESCRIPTION` | ✅ | ❌ | Persona |
| `DEPTH_PROMPT` | ✅ | ❌ | Char depth prompt |

---

## 11. Stopping Strings

### 11.1 Sources (4 types)

| Source | ST | TavernKit | Wave |
|--------|-----|-----------|------|
| Names-based | ✅ | ❌ | 2 |
| Instruct sequences | ✅ | ❌ | 2 |
| Context start markers | ✅ | ❌ | 2 |
| Custom strings | ✅ | ❌ | 2 |

---

## 12. Group Chat

### 12.1 Activation Strategies

| Strategy | ST | TavernKit | Wave |
|----------|-----|-----------|------|
| `NATURAL (0)` | ✅ | ❌ | 4 |
| `LIST (1)` | ✅ | ❌ | 4 |
| `MANUAL (2)` | ✅ | ❌ | 4 |
| `POOLED (3)` | ✅ | ❌ | 4 |

### 12.2 Generation Modes

| Mode | ST | TavernKit | Wave |
|------|-----|-----------|------|
| `SWAP (0)` | ✅ | ❌ | 4 |
| `APPEND (1)` | ✅ | ❌ | 4 |
| `APPEND_DISABLED (2)` | ✅ | ❌ | 4 |

### 12.3 Card Merging

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| Join prefix/suffix | ✅ | ❌ | 4 |
| `<FIELDNAME>` placeholders | ✅ | ❌ | 4 |
| Group nudge | ✅ | ❌ | 4 |

---

## 13. Continue / Impersonate Mode

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| Continue nudge prompt | ✅ | ❌ | 4 |
| Continue prefill | ✅ | ❌ | 4 |
| Continue postfix (4 types) | ✅ | ❌ | 4 |
| Impersonation prompt | ✅ | ❌ | 4 |
| `assistant_impersonation` (Claude) | ✅ | ❌ | 4 |

---

## 14. Context Trimming

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| `context_window_tokens` | ✅ | ❌ | 4 |
| `reserved_response_tokens` | ✅ | ❌ | 4 |
| Examples: trim / always_keep / disable | ✅ | ❌ | 4 |
| Priority-based eviction | ✅ | ❌ | 4 |
| Trim report | ✅ | ❌ | 4 |
| Preserve latest user message | ✅ | ❌ | 4 |

---

## 15. Dialects / Output Formats

| Dialect | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| OpenAI | ✅ | ❌ | 4 |
| Anthropic | ✅ | ❌ | 4 |
| Google (Gemini) | ✅ | ❌ | 4 |
| Cohere | ✅ | ❌ | 4 |
| AI21 | ✅ | ❌ | 4 |
| Mistral | ✅ | ❌ | 4 |
| xAI | ✅ | ❌ | 4 |
| Text Completion | ✅ | ❌ | 4 |

---

## 16. PNG Metadata

| Feature | ST | TavernKit | Wave |
|---------|-----|-----------|------|
| Read `chara` chunk (CCv2) | ✅ | ✅ | 1 |
| Read `ccv3` chunk (CCv3) | ✅ | ✅ | 1 |
| Write PNG metadata | ✅ | ✅ | 1 |
| CharX (`.charx`) import | ✅ | ⏸️ | Wave 6+ |
| JPEG-wrapped CharX | ✅ | ⏸️ | Wave 6+ |

---

## 17. Deferred / Out of Scope

| Feature | ST | TavernKit | Reason |
|---------|-----|-----------|--------|
| CFG (Classifier-Free Guidance) | ✅ | ⏸️ | Complex, low priority |
| Reasoning/Thinking system | ✅ | ⏸️ | Provider-specific |
| Message bias / logit_bias | ✅ | ⏸️ | Provider-specific |
| Tool Calling / Function Calling | ✅ | ⏸️ | Provider-specific |
| STscript full parser | ✅ | ⏸️ | Complexity |
| `activation_regex` (instruct auto-select) | ✅ | 🚫 | Intentional divergence |
| MacroBrowser UI | ✅ | 🚫 | Not applicable (gem has no UI) |
| Chat JSONL metadata | ✅ | ⏸️ | Application layer concern |
| Data Bank / RAG | ✅ | ⏸️ | App layer; TavernKit provides hooks |
| Claude `cache_control` | ✅ | ⏸️ | Provider-specific |
| OpenRouter transforms | ✅ | ⏸️ | Provider-specific |
| Gemini thinking mode | ✅ | ⏸️ | Provider-specific |

---

## Summary by Wave

| Wave | Total Features | Implemented | Remaining |
|------|---------------|-------------|-----------|
| Wave 1 | ~35 | ~35 | 0 |
| Wave 2 | ~50 | 0 | ~50 |
| Wave 3 | ~80 | 0 | ~80 |
| Wave 4 | ~90 | 0 | ~90 |
| Wave 5 | ~20 | 0 | ~20 |

---

## Reference

- ST alignment delta: `docs/rewrite/st-alignment-delta-v1.15.0.md`
- Roadmap: `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md`
- Core interface design: `docs/rewrite/core-interface-design.md`
