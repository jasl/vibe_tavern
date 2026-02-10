# SillyTavern Alignment Delta -- v1.15.0

Date: 2026-01-29 (updated after switching `resources/SillyTavern` to `staging`)

Reference: `resources/SillyTavern/` (vendored, `staging` @ `bba43f33219e41de7331b61f6872f5c7227503a3`, version `1.15.0`)
Compared against: `resources/tavern_kit/docs/` (old alignment docs, also referencing v1.15.0)

## Purpose

Cross-reference the old TavernKit alignment documentation against the actual
SillyTavern v1.15.0 source code. Identify deltas that the new TavernKit rewrite
must address.

---

## 1. Macro System -- Major Deltas

### 1.1 V2 Engine Architecture (was partially documented, now fully mapped)

The old docs (`MACROS_2_ENGINE.md`) described TavernKit's own V2 engine as a
"parser-based, true nesting, depth-first evaluation" system. The actual ST v1.15.0
V2 engine is a **Chevrotain-based lexer-parser-CST-walker pipeline** with
significantly more features than the old docs acknowledged.

**ST V2 architecture (10 source files):**

| Component | File | Role |
|-----------|------|------|
| MacroEngine | `engine/MacroEngine.js` | Top-level orchestrator, pre/post-processor pipeline |
| MacroLexer | `engine/MacroLexer.js` | Multi-mode Chevrotain lexer (10 modes) |
| MacroParser | `engine/MacroParser.js` | CstParser with error recovery |
| MacroCstWalker | `engine/MacroCstWalker.js` | CST evaluator, scoped-block pairing |
| MacroRegistry | `engine/MacroRegistry.js` | Typed macro registration, arg validation |
| MacroEnvBuilder | `engine/MacroEnvBuilder.js` | Lazy env construction with providers |
| MacroFlags | `engine/MacroFlags.js` | Flag parsing (`!`, `?`, `~`, `>`, `/`, `#`) |
| MacroDiagnostics | `engine/MacroDiagnostics.js` | Structured error/warning reporting |
| MacroBrowser | `engine/MacroBrowser.js` | Dynamic documentation browser UI |
| MacroEnv.types | `engine/MacroEnv.types.js` | JSDoc type definitions |

**Definitions (7 files):**
- `definitions/core-macros.js` -- `{{if}}`, `{{else}}`, `{{space}}`, `{{newline}}`, `{{roll}}`, `{{random}}`, `{{pick}}`, `{{banned}}`, `{{outlet}}`, `{{trim}}`, `{{noop}}`, `{{input}}`, `{{maxPrompt}}`, `{{reverse}}`, `{{//}}`
- `definitions/env-macros.js` -- `{{user}}`, `{{char}}`, `{{group}}`, `{{charDescription}}`, `{{persona}}`, etc.
- `definitions/state-macros.js` -- `{{lastGenerationType}}`, `{{hasExtension}}`
- `definitions/chat-macros.js` -- `{{lastMessage}}`, `{{lastMessageId}}`, `{{lastUserMessage}}`, `{{lastCharMessage}}`, `{{firstIncludedMessageId}}`, `{{firstDisplayedMessageId}}`, `{{lastSwipeId}}`, `{{currentSwipeId}}`
- `definitions/time-macros.js` -- `{{time}}`, `{{date}}`, `{{weekday}}`, `{{isotime}}`, `{{isodate}}`, `{{datetimeformat}}`, `{{idleDuration}}`, `{{timeDiff}}`
- `definitions/variable-macros.js` -- `{{setvar}}`, `{{getvar}}`, `{{addvar}}`, `{{incvar}}`, `{{decvar}}`, `{{hasvar}}`/`{{varexists}}`, `{{deletevar}}`/`{{flushvar}}`, + global variants, `{{hasglobalvar}}`/`{{globalvarexists}}`, `{{deleteglobalvar}}`/`{{flushglobalvar}}`
- `definitions/instruct-macros.js` -- 19 instruct macros (see section 4)

### 1.2 NEW: Scoped / Block Macros (`{{macro}}...{{/macro}}`)

**Not documented in old TavernKit docs. Entirely new V2 feature.**

The V2 engine supports opening/closing tag pairs:
```
{{if condition}}content{{/if}}
{{if condition}}then{{else}}other{{/if}}
{{setvar::name}}long multiline value{{/setvar}}
{{trim}}content with whitespace{{/trim}}
{{//}}multiline comment{{///}}
```

Implementation details:
- Closing tag uses `/` flag: `{{/macroName}}`
- Content between tags becomes the last unnamed argument
- Nesting is supported with depth tracking (case-insensitive name matching)
- `#canAcceptScopedContent()` validates arity before accepting scoped content
- Auto-trim + auto-dedent on scoped content by default
- `#` flag (preserveWhitespace) disables auto-trim

**Impact on TavernKit rewrite:**
- V2Engine must implement scoped macro pairing
- Requires `splitOnTopLevelElse()` for `{{if}}...{{else}}...{{/if}}`
- Auto-dedent logic for multi-line scoped content

### 1.3 NEW: `{{if}}` / `{{else}}` Conditional Macro

**Old docs listed `{{#if}}` as "NOT implemented". ST v1.15.0 implements `{{if}}`
(without `#` prefix) as a first-class scoped macro.**

Features:
- `delayArgResolution: true` -- only chosen branch is evaluated (lazy)
- `!` prefix for negation: `{{if !condition}}...{{/if}}`
- Auto-resolve bare macro names: `{{if description}}` resolves `{{description}}` first
- Variable shorthand conditions: `{{if .myvar}}`, `{{if $globalFlag}}`
- Nested `{{if}}/{{else}}/{{/if}}` with depth-tracked splitting
- Both inline (`{{if condition::content}}`) and scoped (`{{if condition}}...{{/if}}`)

**Impact:** This is a major new feature. TavernKit's V2Engine needs conditional
evaluation with lazy branch resolution.

### 1.4 NEW: Variable Shorthand Syntax

**Not documented in old TavernKit docs at all.**

The V2 lexer has dedicated modes and the CST walker has a full `#evaluateVariableExpr`
implementation supporting 16 operators:

| Syntax | Operation | Returns |
|--------|-----------|---------|
| `{{.var}}` | Get local | value |
| `{{$var}}` | Get global | value |
| `{{.var=value}}` | Set local | `""` |
| `{{$var=value}}` | Set global | `""` |
| `{{.var++}}` | Increment local | new value |
| `{{$var--}}` | Decrement global | new value |
| `{{.var+=value}}` | Add to local | `""` |
| `{{.var-=value}}` | Subtract from local | `""` |
| `{{.var\|\|fallback}}` | Logical OR (read) | value or fallback |
| `{{.var??fallback}}` | Nullish coalescing (read) | value or fallback |
| `{{.var\|\|=fallback}}` | Logical OR assign | value |
| `{{.var??=default}}` | Nullish coalescing assign | value |
| `{{.var==value}}` | Equality | `"true"/"false"` |
| `{{.var!=value}}` | Inequality | `"true"/"false"` |
| `{{.var>5}}` | Greater than | `"true"/"false"` |
| `{{.var>=5}}` | Greater than or equal | `"true"/"false"` |
| `{{.var<5}}` | Less than | `"true"/"false"` |
| `{{.var<=5}}` | Less than or equal | `"true"/"false"` |

Lazy value resolution (value expression only evaluated when needed).

**Impact:** TavernKit's V2 lexer/parser needs dedicated variable shorthand
handling. The CST walker needs `#evaluateVariableExpr` with all 16 operators.

### 1.5 NEW: Macro Execution Flags

**Old docs: not documented. ST v1.15.0 defines 6 flags, 2 implemented.**

| Flag | Symbol | Status |
|------|--------|--------|
| Immediate | `!` | Parsed, **not implemented** |
| Delayed | `?` | Parsed, **not implemented** |
| Re-evaluate | `~` | Parsed, **not implemented** |
| Filter/Pipe | `>` | Parsed, **not implemented** (lexer modes exist) |
| Closing Block | `/` | **Implemented** |
| Preserve Whitespace | `#` | **Implemented** |

For TavernKit: implement `/` and `#` flags. Parse but ignore `!`, `?`, `~`, `>`.

### 1.6 NEW: Typed Argument Validation

Macro definitions specify argument types (`string`, `integer`, `number`, `boolean`)
via `MacroValueType`. Arguments are validated at runtime. `strictArgs` controls
error vs warning behavior.

Old TavernKit docs: no mention of typed arguments.

### 1.7 NEW: Pre/Post-Processor Pipeline

The MacroEngine has priority-ordered pre/post-processors:

**Pre-processors:**
1. (priority 10) Legacy `{{time_UTC+5}}` -> `{{time::UTC+5}}` normalization
2. (priority 20) Legacy angle-bracket `<USER>`, `<BOT>`, etc. -> `{{user}}`, `{{char}}`

**Post-processors:**
1. (priority 10) Brace unescaping: `\{` -> `{`, `\}` -> `}`
2. (priority 20) Legacy `{{trim}}` regex removal
3. (priority 30) `ELSE_MARKER` cleanup

External code can register additional processors.

### 1.8 NEW: Macros Not in Old Docs

| Macro | Category | Description |
|-------|----------|-------------|
| `{{space}}` / `{{space::N}}` | UTILITY | Insert space(s) -- old docs listed as "experimental, NOT implemented" |
| `{{newline::N}}` | UTILITY | Insert N newlines -- old docs listed as "experimental" |
| `{{if}}` / `{{else}}` | UTILITY | Conditional (see 1.3) |
| `{{hasExtension}}` | STATE | Check if ST extension is enabled |
| `{{hasvar}}` / `{{varexists}}` | VARIABLE | Check local variable existence |
| `{{deletevar}}` / `{{flushvar}}` | VARIABLE | Delete local variable |
| `{{hasglobalvar}}` / `{{globalvarexists}}` | VARIABLE | Check global variable existence |
| `{{deleteglobalvar}}` / `{{flushglobalvar}}` | VARIABLE | Delete global variable |
| `{{groupNotMuted}}` | NAMES | Group members excluding muted |
| `{{notChar}}` | NAMES | All participants except current speaker |

### 1.9 Updated: `{{pick}}` Seeding

Old docs: "Uses Ruby `Zlib.crc32` + `Random`".
ST v1.15.0: Uses `chatIdHash + rawContentHash + globalOffset + rerollSeed`.
- `chatIdHash` = cached `getStringHash(chatId)`
- `rawContentHash` = `env.contentHash` (hash of full original input)
- `globalOffset` = absolute position in document (ensures identical macros at
  different positions produce different results)
- `rerollSeed` = `chat_metadata.pick_reroll_seed` (user-resettable via `/reroll-pick`)

**Impact:** TavernKit's `{{pick}}` seeding should match this 4-component seed.

**Current TavernKit (2026-02-02):** Deterministic `{{pick}}` is implemented, but
the seed does **not** yet match ST exactly (no reroll seed; Ruby `Random` +
`Zlib.crc32` vs JS `seedrandom`). This is tracked as a known delta.

### 1.10 Updated: `{{banned}}` Side Effects

Old docs: "No side effects (removed only)".
ST v1.15.0: If `main_api === 'textgenerationwebui'`, pushes to
`textgenerationwebui_banned_in_macros` array. So it DOES have side effects
for Text Completion backends.

**Impact:** TavernKit divergence note should acknowledge this.

### 1.11 Macro Count Summary

| Category | Count | Key Examples |
|----------|-------|-------------|
| UTILITY | 10 | `space`, `newline`, `noop`, `trim`, `if`, `else`, `input`, `reverse`, `//`, `banned` |
| RANDOM | 3 | `roll`, `random`, `pick` |
| NAMES | 5 | `user`, `char`, `group`, `groupNotMuted`, `notChar` |
| CHARACTER | 11 | `charPrompt`, `charInstruction`, `charDescription`, `charPersonality`, `charScenario`, `persona`, `mesExamples`, `mesExamplesRaw`, `charDepthPrompt`, `charCreatorNotes`, `charVersion`, `model`, `original`, `isMobile` |
| CHAT | 8 | `lastMessage`, `lastMessageId`, `lastUserMessage`, `lastCharMessage`, `firstIncludedMessageId`, `firstDisplayedMessageId`, `lastSwipeId`, `currentSwipeId` |
| TIME | 8 | `time`, `date`, `weekday`, `isotime`, `isodate`, `datetimeformat`, `idleDuration`, `timeDiff` |
| VARIABLE | 14 | `setvar`, `getvar`, `addvar`, `incvar`, `decvar`, `hasvar`, `deletevar` + global variants |
| PROMPTS | 19 | instruct macros (see section 4) |
| STATE | 3 | `maxPrompt`, `lastGenerationType`, `hasExtension` |
| **Total** | **~81** | (including aliases) |

### 1.12 Macro Registration: `delayArgResolution`

Macros may declare `delayArgResolution: true` which tells the CST walker to pass
raw (unevaluated) argument nodes as `LazyValue` wrappers. The handler decides
when/if to resolve each arg. This is critical for `{{if}}`/`{{else}}` (only the
chosen branch is evaluated) and for variable shorthand assignment operators
(the value expression is only evaluated if needed for `||=`, `??=`).

**Impact:** TavernKit V2Engine must support lazy arg resolution.

---

## 2. World Info / Lore -- Deltas

### 2.1 Entry Fields (comprehensive from ST source)

The old docs covered most fields. New/updated fields found in ST v1.15.0:

| Field | Old Docs | ST v1.15.0 | Delta |
|-------|----------|-----------|-------|
| `matchPersonaDescription` | Not listed | `boolean, default false` | **NEW** -- match against persona description |
| `matchCharacterDescription` | Not listed | `boolean, default false` | **NEW** -- match against character description |
| `matchCharacterPersonality` | Not listed | `boolean, default false` | **NEW** -- match against personality |
| `matchCharacterDepthPrompt` | Not listed | `boolean, default false` | **NEW** -- match against depth prompt |
| `matchScenario` | Not listed | `boolean, default false` | **NEW** -- match against scenario |
| `matchCreatorNotes` | Not listed | `boolean, default false` | **NEW** -- match against creator notes |
| `characterFilterNames` | Not listed | `array, default []` | **NEW** -- character name filter |
| `characterFilterTags` | Not listed | `array, default []` | **NEW** -- character tag filter |
| `characterFilterExclude` | Not listed | `boolean, default false` | **NEW** -- invert character filter |
| `triggers` | Not listed | `array, default []` | **NEW** -- generation type trigger filter |
| `outletName` | Partially | `string, default ''` | Confirmed outlet support |
| `useProbability` | Not listed | `boolean, default true` | **NEW** -- enable/disable probability check |
| `vectorized` | Not listed | `boolean, default false` | Noted (vector embedding flag) |

**Impact:** TavernKit's `Lore::Entry` data structure must include all 6 `match*`
fields, character filter fields, and the `triggers` array.

### 2.2 Global Scan Data Matching

ST allows entries to opt-in to match against non-chat data sources via boolean flags.
These fields are concatenated to the scan buffer when their respective entry-level
flags are true:

- persona description, character description, character personality,
  character depth prompt, scenario, creator notes

Old docs mentioned "scan buffer composition" but did not enumerate the per-entry
opt-in mechanism via `matchPersonaDescription`, etc.

### 2.3 Generation Type Triggers

The `triggers` field (array of strings) filters entries by the type of generation:
`'normal'`, `'continue'`, `'impersonate'`, `'swipe'`, `'quiet'`, etc.

If `triggers` is non-empty, the entry only activates when the current generation
trigger matches one of the listed values.

**Impact:** TavernKit's scan context must carry a `trigger` field, and the
scanning loop must check it.

### 2.4 Character Filtering

Entries support filtering by character identity:
- `characterFilter.names[]` -- character identifiers
- `characterFilter.tags[]` -- tag IDs
- `characterFilter.isExclude` -- invert (true = exclude matching chars)

**Impact:** New filtering logic in TavernKit's Lore::Engine scan loop.

### 2.5 Timed Effects -- Confirmed Behavior

Old docs correctly described sticky/cooldown/delay. ST source confirms:
- Sticky entries skip probability re-rolls
- Cooldown starts when sticky ends
- Delay is computed from `chat.length < entry.delay` (not stored in metadata)
- Unprotected effects are cleaned up when chat doesn't advance

### 2.6 Import Formats

ST supports importing lorebooks from:
- SillyTavern native JSON
- Character Book (V2 spec embedded)
- Novel AI (detected by `lorebookVersion`)
- Agnai (detected by `kind === 'memory'`)
- RisuAI (detected by `type === 'risu'`)
- PNG (embedded in PNG metadata under `naidata`)

Old docs: only mentioned ST native + Character Book.

**Impact:** TavernKit should support at least ST native + Character Book.
Novel AI / Agnai / RisuAI import are lower priority but worth noting.

### 2.7 Events / Extension Points

ST emits events during WI processing:
- `WORLDINFO_FORCE_ACTIVATE` -- external forced activation
- `WORLDINFO_SCAN_DONE` -- per-loop-iteration extension point
- `WORLDINFO_ENTRIES_LOADED` -- entries loaded before scan
- `WORLD_INFO_ACTIVATED` -- after scanning with all results

**Impact:** TavernKit's Lore::Engine should support hooks/callbacks at these points,
at minimum `force_activate` and `on_scan_done`.

---

## 3. Prompt Manager / Assembly -- Deltas

### 3.1 Default Prompt Identifiers (confirmed)

ST v1.15.0 has 12 default prompts. The old docs correctly listed them.
No delta.

### 3.2 Injection Position / Depth Semantics (confirmed)

Old docs correctly documented:
- `INJECTION_POSITION.RELATIVE (0)` vs `ABSOLUTE (1)`
- Depth 0 = at end, depth N = N positions from end
- Same depth: grouped by `injection_order` (descending), then by role
  (`system` -> `user` -> `assistant`)
- Same depth+order+role entries merged into single message

**No delta.** ST source confirms this behavior exactly.

### 3.3 Overridable Prompts

Only `'main'` and `'jailbreak'` can be overridden by character cards.
Blocked when `forbid_overrides: true`.

Old docs: correctly documented. **No delta.**

### 3.4 ChatCompletion Token Budget Model

ST source confirms:
- Budget = `max_context - max_tokens` (reserved for response)
- 3 tokens reserved for assistant reply primer
- `canAfford()` checks before adding each collection
- `squashSystemMessages()` merges consecutive system messages (without `name` field)
- Excludes `newMainChat`, `newChat`, `groupNudge` from squashing

**No major delta.** Old docs covered this.

### 3.5 Extension Prompt Integration

ST injects known extension prompts into `main`'s collection:
- `summary` (from `1_memory`)
- `authorsNote` (from `2_floating_prompt`)
- `vectorsMemory` (from `3_vectors`)
- `vectorsDataBank` (from `4_vectors_data_bank`)
- `smartContext` (from `chromadb`)
- `personaDescription` (if position is IN_PROMPT)

**Impact:** TavernKit's step chain should have injection points for
extensions. This maps cleanly to the InjectionRegistry pattern.

### 3.6 Message Class Multimodal Support

ST's `Message` class supports:
- `addImage(image)` -- data URL with detail level, 85/170 tokens per tile
- `addVideo(video)` -- 263 tokens/second estimate
- `addAudio(audio)` -- 32 tokens/second estimate

Old docs: did not mention multimodal support.

**Impact:** TavernKit's `PromptBuilder::Message` should support multimodal content
(at minimum images). Lower priority than the core text-only prompt path, but
worth noting for future API design.

### 3.7 Default Message Templates

ST defines default templates with macro placeholders:

| Template | Default |
|----------|---------|
| `main` | `"Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}."` |
| `enhance_definitions` | `"If you have more knowledge of {{char}}, add to the character's lore..."` |
| `impersonation` | `"[Write your next reply from the point of view of {{user}}, ...]"` |
| `new_chat` | `"[Start a new Chat]"` |
| `new_group_chat` | `"[Start a new group chat. Group members: {{group}}]"` |
| `new_example_chat` | `"[Example Chat]"` |
| `continue_nudge` | `"[Continue your last message without repeating its original content.]"` |
| `group_nudge` | `"[Write the next reply only as {{char}}.]"` |
| `personality_format` | `"{{personality}}"` |
| `scenario_format` | `"{{scenario}}"` |
| `wi_format` | `"{0}"` |

**Impact:** TavernKit's ST::Preset should define these as defaults with
macro references.

---

## 4. Instruct Mode -- Deltas

### 4.1 All Configurable Properties (confirmed 24)

ST v1.15.0 `power_user.instruct` has 24 properties. Old docs listed most of them.

Newly confirmed / more precisely documented:

| Property | Notes |
|----------|-------|
| `first_input_sequence` | First user message prefix |
| `last_input_sequence` | Last user message prefix |
| `first_output_sequence` | First assistant prefix |
| `last_output_sequence` | Last assistant prefix (generation prompt) |
| `story_string_prefix` | Before story string (e.g. `<s>`) |
| `story_string_suffix` | After story string |
| `sequences_as_stop_strings` | Add all sequences as stop strings |
| `system_same_as_user` | Use input_sequence for system messages |
| `bind_to_context` | Auto-select matching context template |
| `activation_regex` | Auto-match model names |

**No major delta.** Old docs covered these. `activation_regex` remains
"not implemented" in TavernKit (intentional divergence).

### 4.2 Instruct Macros (19 total)

Complete list from ST `instruct-macros.js`:

| Macro | Aliases | Value Source |
|-------|---------|-------------|
| `instructStoryStringPrefix` | -- | `story_string_prefix` |
| `instructStoryStringSuffix` | -- | `story_string_suffix` |
| `instructUserPrefix` | `instructInput` | `input_sequence` |
| `instructUserSuffix` | -- | `input_suffix` |
| `instructAssistantPrefix` | `instructOutput` | `output_sequence` |
| `instructAssistantSuffix` | `instructSeparator` | `output_suffix` |
| `instructSystemPrefix` | -- | `system_sequence` |
| `instructSystemSuffix` | -- | `system_suffix` |
| `instructFirstAssistantPrefix` | `instructFirstOutputPrefix` | `first_output_sequence \|\| output_sequence` |
| `instructLastAssistantPrefix` | `instructLastOutputPrefix` | `last_output_sequence \|\| output_sequence` |
| `instructStop` | -- | `stop_sequence` |
| `instructUserFiller` | -- | `user_alignment_message` |
| `instructSystemInstructionPrefix` | -- | `last_system_sequence` |
| `instructFirstUserPrefix` | `instructFirstInput` | `first_input_sequence \|\| input_sequence` |
| `instructLastUserPrefix` | `instructLastInput` | `last_input_sequence \|\| input_sequence` |
| `defaultSystemPrompt` | `instructSystem`, `instructSystemPrompt` | `sysprompt.content` |
| `systemPrompt` | -- | Character prompt if `prefer_character_prompt`, else sysprompt |
| `exampleSeparator` | `chatSeparator` | `context.example_separator` |
| `chatStart` | -- | `context.chat_start` |

Old docs covered most of these. New additions:
- `instructStoryStringPrefix` / `instructStoryStringSuffix`
- `instructUserSuffix`
- `instructSystemPrefix` / `instructSystemSuffix`
- `instructFirstUserPrefix` / `instructLastUserPrefix`
- `instructUserFiller`
- `instructSystemInstructionPrefix`
- `defaultSystemPrompt` (with `instructSystem` / `instructSystemPrompt` aliases)
- `systemPrompt` (character-override-aware)

**Impact:** TavernKit's instruct macro pack needs all 19 macros with correct
aliases and fallback behavior.

### 4.3 Names Behavior

```javascript
names_behavior_types = {
    NONE: 'none',     // Never prepend names
    FORCE: 'force',   // Only for group members / force_avatar
    ALWAYS: 'always', // Always prepend "Name: " to content
}
```

Old docs correctly documented. **No delta.**

### 4.4 System Prompt Separation

ST v1.15.0 separates system prompt from instruct mode:
- `power_user.sysprompt.content` -- the system prompt text
- `power_user.sysprompt.enabled` -- toggle
- `power_user.sysprompt.post_history` -- optional post-history text
- Migration path from old `instruct.system_prompt` field

**Impact:** TavernKit should model system prompt as a separate concept from
instruct mode, accessible via `{{systemPrompt}}` and `{{defaultSystemPrompt}}`
macros.

---

## 5. Divergences Update

### 5.1 Previously Listed -- Still Valid

These divergences from old `SILLYTAVERN_DIVERGENCES.md` remain correct:

1. Legacy angle-bracket macros not implemented (ST pre-processor handles them)
2. `data.extensions.fav` not interpreted
3. Character-linked lorebooks are name-based
4. Legacy preset fields ignored
5. No `:claude_prompt` dialect
6. Preset-level Anthropic toggles ignored
7. Auto without human: round-limited
8. Unified TurnScheduler
9. User input priority
10. Pooled `reply_order`
11. JS RegExp best-effort conversion
12. `{{pick}}` seeding differs (Ruby vs JS seedrandom)
13. `{{banned}}` side effects differ (see 1.10)

### 5.2 Previously Listed -- Now Partially Resolved in ST

These were listed as "NOT implemented" but ST v1.15.0 HAS them:

| Feature | Old Status | ST v1.15.0 | TavernKit Action |
|---------|-----------|-----------|-----------------|
| `{{#if}}` / `{{#unless}}` conditionals | NOT implemented | **`{{if}}` / `{{else}}` implemented** (no `#` prefix; `#` is preserveWhitespace flag) | Implemented (V2Engine) |
| `{{space}}` / `{{space::N}}` | NOT implemented | **Implemented** | Implemented (core macros pack) |
| `{{newline::N}}` | NOT implemented (experimental) | **Implemented** (count arg) | Implemented (core macros pack) |
| Handlebars conditionals | NOT implemented | Replaced by `{{if}}` block syntax | Implemented (scoped `{{if}}`) |

### 5.3 New Divergences to Document

| Feature | ST v1.15.0 | TavernKit Action |
|---------|-----------|-----------------|
| Variable shorthand (`{{.var}}`, `{{$var}}`, 16 operators) | Implemented | Implemented (V2Engine) |
| `{{hasExtension}}` macro | Checks ST extension system | Implemented (platform attrs-driven) |
| `{{hasvar}}` / `{{deletevar}}` / `{{hasglobalvar}}` / `{{deleteglobalvar}}` | Implemented | Implemented (variables macros pack) |
| `{{groupNotMuted}}` | Group members excluding muted | Implemented (env macros pack) |
| Entry field: 6 `match*` flags | Per-entry opt-in for non-chat scan data | Implemented (Lore::EntryExtensions) |
| Entry field: `characterFilter*` | Character/tag filter with exclude | Implemented (Lore::EntryExtensions) |
| Entry field: `triggers` | Generation type filter | Implemented (Lore::EntryExtensions) |
| Entry field: `useProbability` | Enable/disable probability check | Implemented (Lore::EntryExtensions) |
| Macro flags (`!`, `?`, `~`, `>`) | Parsed but unimplemented | Implemented (parse + ignore) |
| Pre/post-processor pipeline | Extensible processing around evaluation | Implemented |
| Typed macro arguments | Runtime type validation | Implemented |
| Multimodal Message content | Images, video, audio | Deferred (future) |
| System prompt as separate entity | `sysprompt.content` separate from instruct | Implemented (macros; content is app-supplied) |
| MacroBrowser documentation UI | Dynamic searchable UI | Not applicable (gem has no UI) |

---

## 8. Context Template System -- New Section

**Not covered in previous alignment docs. Discovered in second scan.**

Source: `power-user.js` (lines 87-263), `instruct-mode.js`

### 8.1 Story String (Handlebars Template)

Default template:
```
{{#if system}}{{system}}\n{{/if}}{{#if description}}{{description}}\n{{/if}}{{#if personality}}{{char}}'s personality: {{personality}}\n{{/if}}{{#if scenario}}Scenario: {{scenario}}\n{{/if}}{{#if persona}}{{persona}}\n{{/if}}
```

Placeholders (all conditionally injected):
- `{{system}}` -- System prompt
- `{{description}}` -- Character description
- `{{personality}}` -- Character personality (prefixed with `"{{char}}'s personality: "`)
- `{{scenario}}` -- Scenario (prefixed with `"Scenario: "`)
- `{{persona}}` -- User persona description
- `{{char}}` -- Character name
- `{{wiBefore}}` / `{{wiAfter}}` -- World Info before/after positions
- `{{anchorBefore}}` / `{{anchorAfter}}` -- Author's note anchors

Implementation note:
- Some context presets include **ST macro tokens** inside `story_string` (for
  example `{{trim}}` in `default/content/presets/context/*.json`).
  TavernKit should render Handlebars blocks + known placeholders only, and
  leave unknown `{{...}}` macros intact for macro expansion.

### 8.2 Context Template Fields

| Field | Default | Description |
|-------|---------|-------------|
| `story_string` | Handlebars template above | Story string template |
| `chat_start` | `"***"` | Chat start marker |
| `example_separator` | `"***"` | Example separator marker |
| `story_string_position` | `IN_PROMPT (0)` | Where story string is injected |
| `story_string_depth` | `1` | Depth when position is IN_CHAT |
| `story_string_role` | `SYSTEM (0)` | Role when position is IN_CHAT |
| `use_stop_strings` | `true` | Add chat_start/example_separator to stopping strings |

`story_string_position` uses `extension_prompt_types`:
- `IN_PROMPT (0)` -- After system prompt
- `IN_CHAT (1)` -- At message depth within chat history

**Impact:** TavernKit's `SillyTavern::ContextTemplate` must implement
Handlebars-based story string compilation with all placeholders, plus
chat_start/example_separator with stop-string integration. Macro tokens inside
the template (e.g. `{{trim}}`) are expanded later by the Macro engine.

---

## 9. Persona Description System -- New Section

Source: `personas.js`, `power-user.js` (lines 111-119)

### 9.1 Persona Description Positions

```
persona_description_positions = {
    IN_PROMPT:  0,   // Injected into main prompt
    AFTER_CHAR: 1,   // DEPRECATED (use IN_PROMPT)
    TOP_AN:     2,   // Top of Author's Note
    BOTTOM_AN:  3,   // Bottom of Author's Note
    AT_DEPTH:   4,   // Injected at specific message depth
    NONE:       9,   // Disabled
}
```

### 9.2 Persona Descriptor Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `description` | string | `""` | Persona description text |
| `position` | number | `IN_PROMPT (0)` | Injection position enum |
| `depth` | number | `2` | Message depth for AT_DEPTH position |
| `role` | number | `SYSTEM (0)` | Role for depth injection (0=system, 1=user, 2=assistant) |
| `lorebook` | string | `""` | Associated lorebook name |
| `title` | string | `""` | Display title |
| `connections` | array | `[]` | Character/group associations |

### 9.3 Lock System

Three lock types (ascending priority):
1. **Default**: `power_user.default_persona` (all chats)
2. **Character**: `persona_descriptions[avatarId].connections[]`
3. **Chat**: `chat_metadata.persona` (current chat only)

**Impact:** TavernKit's persona description injection needs to support all
5 positions and the depth/role configuration. The lock system is UI-specific
(not needed in gem), but the injection positions affect prompt assembly.

---

## 10. Author's Note System -- New Section

Source: `extensions/2_floating_prompt/` (authors-note.js)

### 10.1 Core Fields

| Field | Metadata Key | Default | Description |
|-------|-------------|---------|-------------|
| note text | `note_prompt` | `""` | Author's note content |
| interval | `note_interval` | `1` | Insert every N messages |
| depth | `note_depth` | `4` | Message depth for injection |
| position | `note_position` | `1 (IN_CHAT)` | Injection position |
| role | `note_role` | `0 (SYSTEM)` | Message role |

### 10.2 Character-Specific Author's Note

Per-character overrides stored in `extension_settings.note.chara[]`:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Character filename |
| `prompt` | string | Character-specific note text |
| `useChara` | boolean | Enable/disable |
| `position` | number | 0=replace, 1=before, 2=after main note |

Position enum (`chara_note_position`):
- `replace (0)` -- Replace global note entirely
- `before (1)` -- Prepend before global note
- `after (2)` -- Append after global note

### 10.3 Frequency-Based Insertion

```
messagesTillInsertion = lastMessageNumber >= interval
    ? (lastMessageNumber % interval)
    : (interval - lastMessageNumber)
shouldAddPrompt = messagesTillInsertion == 0
```

When `interval=1`: Always insert.
When `interval=N`: Insert every N user messages.

**Impact:** TavernKit's `SillyTavern::PromptBuilder::Steps::Injection` needs
interval-based author's note insertion with character-specific overrides.
The `Preset` must carry author's note defaults.

---

## 11. Stopping Strings Assembly -- New Section

Source: `script.js` (line 2913), `instruct-mode.js` (line 300), `power-user.js`

### 11.1 Four Sources (Combined in Order)

**1. Names-based stops** (if `context.names_as_stop_strings` enabled):
- `"\n{characterName}:"`
- `"\n{userName}:"`
- Group members (if group chat): `"\n{memberName}:"`

**2. Instruct mode sequences** (from `getInstructStoppingSequences()`):
- Requires `instruct.enabled` AND `instruct.sequences_as_stop_strings`
- Includes: `stop_sequence`, `input_sequence`, `output_sequence`,
  `first_output_sequence`, `last_output_sequence`, `system_sequence`,
  `last_system_sequence`
- Optionally wrapped with `\n` if `instruct.wrap` enabled
- Macro substitution if `instruct.macro` enabled

**3. Context start markers** (if `context.use_stop_strings` enabled):
- `"\n{chat_start}"` (macro-substituted)
- `"\n{example_separator}"` (macro-substituted)

**4. Custom stopping strings** (`power_user.custom_stopping_strings`):
- Permanent: JSON array string (parsed, validated)
- Ephemeral: `EPHEMERAL_STOPPING_STRINGS` runtime array
- Macro substitution if `custom_stopping_strings_macro` enabled

Single-line mode: prepends `"\n"` to all stops.
All sources deduplicated before sending to API.

**Impact:** TavernKit's `SillyTavern::Preset` should expose a
`#stopping_strings(context)` method that assembles all 4 sources.
The Instruct sequences source requires the Instruct module.

---

## 12. Extension Prompt Injection Framework -- New Section

Source: `script.js` (lines 598, 3184, 8689), `openai.js`

### 12.1 Enums

```
extension_prompt_types = {
    NONE:          -1,  // Hidden (WI scanning only, not in prompt)
    IN_PROMPT:      0,  // After story string (system position)
    IN_CHAT:        1,  // Within chat history at depth
    BEFORE_PROMPT:  2,  // Before story string
}

extension_prompt_roles = {
    SYSTEM:    0,
    USER:      1,
    ASSISTANT: 2,
}
```

### 12.2 Extension Prompt Data Structure

```
extension_prompts[key] = {
    value:    String,            // Prompt text
    position: Number,           // extension_prompt_types
    depth:    Number,           // 0 = most recent, up to 10000
    scan:     Boolean,          // Include in WI scanning
    role:     Number,           // extension_prompt_roles
    filter:   Function | null,  // Optional async filter closure
}
```

### 12.3 Built-in Extension Prompt IDs

| ID | Extension | Default Position | Default Depth |
|----|-----------|-----------------|---------------|
| `1_memory` | Memory/Summarize | IN_PROMPT | 2 |
| `2_floating_prompt` | Author's Note | IN_CHAT | 2 |
| `3_vectors` | Vectors/RAG (chat) | IN_PROMPT | 2 |
| `4_vectors_data_bank` | Data Bank | IN_PROMPT | 4 |
| `chromadb` | ChromaDB (legacy) | varies | varies |
| `PERSONA_DESCRIPTION` | Persona system | IN_PROMPT | 0 |
| `DEPTH_PROMPT` | Char depth prompt | IN_CHAT | varies |

### 12.4 Integration with Prompt Assembly

1. System prompts: gathers BEFORE_PROMPT + IN_PROMPT prompts, merges with
   PromptManager collection
2. Chat injection: for each depth level, retrieves IN_CHAT prompts grouped
   by role, injects at message boundaries

**Impact:** TavernKit's `SillyTavern::InjectionRegistry` maps
directly to this framework. The `PromptBuilder::Steps::Injection` step consumes
registered extension prompts and injects them at the correct positions.

---

## 13. Group Chat System -- New Section

Source: `group-chats.js`

### 13.1 Activation Strategies

```
group_activation_strategy = {
    NATURAL: 0,   // AI decides who responds
    LIST:    1,   // Cycle through member list
    MANUAL:  2,   // User selects speaker
    POOLED:  3,   // Weighted random from pool
}
```

### 13.2 Generation Modes

```
group_generation_mode = {
    SWAP:             0,  // Replace previous character response
    APPEND:           1,  // Append to conversation (enabled members only)
    APPEND_DISABLED:  2,  // Append including disabled members
}
```

### 13.3 Card Merging (APPEND modes)

In APPEND and APPEND_DISABLED modes, group member card fields are merged:
- Collects `description`, `personality`, `scenario`, `mes_examples` from
  all enabled (or all for APPEND_DISABLED) members
- Applies prefix/suffix via `generation_mode_join_prefix` / `_suffix`
- Supports `<FIELDNAME>` placeholder in join templates
- Joined with newlines using `replaceAndPrepareForJoin()` + `customTransform()`

### 13.4 Group Configuration Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `activation_strategy` | number | `NATURAL (0)` | Who responds next |
| `generation_mode` | number | `SWAP (0)` | How responses are generated |
| `generation_mode_join_prefix` | string | `""` | Prefix for merged fields |
| `generation_mode_join_suffix` | string | `""` | Suffix for merged fields |
| `allow_self_responses` | boolean | `false` | Same character responds twice |
| `disabled_members` | array | `[]` | Muted member avatars |
| `auto_mode_delay` | number | `5` | Auto-mode delay (seconds) |
| `hideMutedSprites` | boolean | `false` | Hide muted sprites |

### 13.5 Group Nudge

Default: `"[Write the next reply only as {{char}}.]"`
Field: `oai_settings.group_nudge_prompt`
Positioned as system message (identifier: `'groupNudge'`).
Not added for impersonate-type requests.

**Impact:** TavernKit's `SillyTavern::GroupContext` must implement
activation strategies, generation modes, and card merging. The
`PromptBuilder::Steps::PinnedGroups` step handles group-specific prompt slots.

---

## 14. Continue / Impersonate Mode -- New Section

Source: `openai.js` (lines 856-876, 1115, 2618)

### 14.1 Continue Mode

| Field | Default | Description |
|-------|---------|-------------|
| `continue_prefill` | `false` | Use assistant prefill for continue |
| `continue_postfix` | `" "` (space) | Text appended after continue |
| `continue_nudge_prompt` | `"[Continue your last message...]"` | System nudge |

Postfix types:
```
continue_postfix_types = {
    NONE:           "",
    SPACE:          " ",
    NEWLINE:        "\n",
    DOUBLE_NEWLINE: "\n\n",
}
```

Continue mode alters prompt assembly:
1. If `continue_prefill=false`: adds nudge prompt as system message,
   displaces last message into separate collection
2. If `continue_prefill=true`: prepends assistant content as prefill,
   skips nudge prompt

### 14.2 Impersonate Mode

| Field | Default | Description |
|-------|---------|-------------|
| `impersonation_prompt` | `"[Write your next reply from {{user}}'s POV...]"` | System prompt |
| `assistant_impersonation` | `""` | Claude-specific prefill for impersonate |

Impersonate mode:
- Adds impersonation_prompt to system prompts (identifier: `'impersonate'`)
- Skips group nudge
- For Claude: uses `assistant_impersonation` as assistant prefill instead of
  regular `assistant_prefill`

### 14.3 Assistant Prefill (Claude-specific)

| Field | Context | Description |
|-------|---------|-------------|
| `assistant_prefill` | Normal/quiet generation | Prepended to assistant response |
| `assistant_impersonation` | Impersonate mode | Impersonate-specific prefill |

Only applied when `chat_completion_source === 'claude'` and not in
continue+prefill mode.

**Impact:** TavernKit's `SillyTavern::PromptBuilder::Steps::PlanAssembly` needs
continue/impersonate mode awareness. The `Preset` must carry nudge prompts,
postfix config, and prefill settings.

---

## 15. Tokenizer System (Informational) -- New Section

Source: `tokenizers.js`

### 15.1 ST Tokenizer IDs (20 types)

| ID | Name | Description |
|----|------|-------------|
| 0 | NONE | Fallback (3.35 chars/token ratio) |
| 1 | GPT2 | GPT-2 tokenizer |
| 2 | OPENAI | OpenAI (gpt-3.5, gpt-4) |
| 3 | LLAMA | Llama 1/2 |
| 4 | NERD | NovelAI Clio |
| 5 | NERD2 | NovelAI Kayra |
| 6 | API_CURRENT | Current API remote tokenizer |
| 7 | MISTRAL | Mistral |
| 8 | YI | Yi models |
| 9 | API_TEXTGENERATIONWEBUI | Text Gen WebUI remote |
| 10 | API_KOBOLD | KoboldAI remote |
| 11 | CLAUDE | Claude |
| 12 | LLAMA3 | Llama 3 |
| 13 | GEMMA | Gemma |
| 14 | JAMBA | Jamba (AI21) |
| 15 | QWEN2 | Qwen2 |
| 16 | COMMAND_R | Cohere Command R |
| 17 | NEMO | Nemo/Pixtral |
| 18 | DEEPSEEK | DeepSeek |
| 19 | COMMAND_A | Cohere Command A |
| 99 | BEST_MATCH | Auto-detection (model name matching) |

### 15.2 BEST_MATCH Detection Logic

Priority-based detection:
1. NovelAI: model name → NERD/NERD2/LLAMA3
2. KoboldAI: remote API if available → API_KOBOLD
3. Text Gen WebUI: remote API if available → API_TEXTGENERATIONWEBUI
4. OpenRouter/DreamGen: model-specific detection
5. Model name substring matching:
   `llama3` → LLAMA3, `mistral` → MISTRAL, `gemma` → GEMMA, etc.
6. Default fallback: LLAMA

**Impact:** TavernKit uses `tiktoken_ruby` for token estimation (Core layer).
ST tokenizer IDs are informational -- they tell TavernKit which tokenizer the
frontend expects. The `TokenEstimator` should default to cl100k (GPT-4) but
allow callers to specify a tokenizer hint for more accurate estimation.

---

## 16. Additional Subsystems (Deferred) -- New Section

These subsystems were identified but are explicitly deferred (out of scope for
the prompt-assembly gem; see `docs/backlogs.md`) or are not
applicable:

### 16.1 CFG (Classifier-Free Guidance)

Source: `cfg-scale.js`

3-tier hierarchy: chat > character > global.
Fields: `guidance_scale`, `negative_prompt`, `positive_prompt`.
Metadata keys: `cfg_guidance_scale`, `cfg_negative_prompt`, `cfg_positive_prompt`,
`cfg_prompt_combine`, `cfg_groupchat_individual_chars`, `cfg_prompt_insertion_depth`,
`cfg_prompt_separator`.

Assembly: cascades from chat → character → global, skips scale=1.0 (no effect).
Combines prompts based on `cfg_prompt_combine` flags.

### 16.2 Reasoning/Thinking System

Source: `reasoning.js`

Templates: DeepSeek (`<think>`), Claude (`<thinking>`), Gemini (`<thought>`).
Auto-parse: `power_user.reasoning.auto_parse` extracts thinking blocks from
model response. Multiple extraction paths per API source (OpenAI/TextGen/etc.).
Encrypted signatures: Gemini uses `thoughtSignature` for multi-turn context.
Hidden reasoning models: `o1*`, `o3*`, `gpt-4.5*`.

### 16.3 Message Bias / Logit Bias

Source: `logit-bias.js`, `openai.js`

Bias presets: `bias_presets[name] = [{id, text, value}, ...]`.
Text patterns: `{verbatim}`, `[token_ids]`, `plain text`.
Integration: cached via `calculateLogitBias()`, sent as `logit_bias` field.

### 16.4 Regex Scripts Extension

Per-character regex find/replace rules applied to messages at runtime.

### 16.5 Memory/Summarize Extension

Chat summarization via LLM, injected as extension prompt `1_memory`.

### 16.6 Vector/RAG Extension

Semantic similarity search over chat history and data bank files.
Injected as extension prompts `3_vectors` and `4_vectors_data_bank`.

### 16.7 Tool Calling

`ToolManager.isToolCallingSupported()` gates tool use.
`function_calling` preset field enables/disables.
ST-specific implementation detail, not relevant to prompt assembly gem.

---

## 17. Chat Completion Preset Fields (Complete List) -- New Section

Source: `openai.js` (settingsToUpdate, line 273-369)

These are all fields that affect prompt building and API request generation.
Fields marked **(conn)** are connection settings, not part of prompt logic.

### 17.1 Sampling Parameters

| Field | Default | Range |
|-------|---------|-------|
| `temp_openai` | 1.0 | 0.0-2.0 |
| `top_p_openai` | 1.0 | 0.01-0.99 |
| `top_k_openai` | 0 | 0+ |
| `top_a_openai` | 0 | 0-1 |
| `min_p_openai` | 0 | 0-1 |
| `freq_pen_openai` | 0 | 0-2 |
| `pres_pen_openai` | 0 | 0-2 |
| `repetition_penalty_openai` | 1 | 0.5-2.0 |

### 17.2 Token Budget

| Field | Default |
|-------|---------|
| `openai_max_context` | 4096 |
| `openai_max_tokens` | 300 |
| `max_context_unlocked` | false |

### 17.3 Prompt Management Fields

| Field | Description |
|-------|-------------|
| `prompts` | Prompt manager collection |
| `prompt_order` | Prompt ordering config |
| `bias_preset_selected` | Active logit bias preset |
| `use_sysprompt` | Use system prompt |
| `squash_system_messages` | Merge consecutive system messages |
| `names_behavior` | How character names are handled |
| `custom_prompt_post_processing` | Post-processing mode |

### 17.4 Template Prompts

| Field | Default |
|-------|---------|
| `send_if_empty` | Fallback if no response |
| `impersonation_prompt` | User impersonation context |
| `new_chat_prompt` | Solo chat greeting |
| `new_group_chat_prompt` | Group chat greeting |
| `new_example_chat_prompt` | Example chat greeting |
| `continue_nudge_prompt` | Continue generation nudge |
| `group_nudge_prompt` | Group generation nudge |
| `assistant_prefill` | Claude response prefix |
| `assistant_impersonation` | Claude impersonation prefix |

### 17.5 Format Templates

| Field | Default |
|-------|---------|
| `wi_format` | `"{0}"` |
| `scenario_format` | `"{{scenario}}"` |
| `personality_format` | `"{{personality}}"` |

### 17.6 Generation Options

| Field | Default | Description |
|-------|---------|-------------|
| `n` | 1 | Number of completions |
| `seed` | -1 | Determinism seed |
| `stream_openai` | false | Response streaming |
| `continue_prefill` | false | Auto-complete continue |
| `continue_postfix` | `" "` | Text after continue |
| `function_calling` | false | Tool calling |
| `show_thoughts` | true | Show reasoning |
| `reasoning_effort` | `"auto"` | o1/o3 effort level |

**Impact:** TavernKit's `SillyTavern::Preset` should model all
prompt-affecting fields (sections 17.1-17.5). Streaming, tool calling, and
provider-specific model selection (17.6, connection settings) are not relevant
to the prompt assembly gem.
