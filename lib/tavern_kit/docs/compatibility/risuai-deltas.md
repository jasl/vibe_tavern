# RisuAI Alignment Delta (Source Scan)

Date: 2026-01-29
Source: `resources/Risuai/src/` (full source tree scan)
Cross-reference: `lib/tavern_kit/docs/notes/st-risuai-parity.md` (prior parity checklist)

## Purpose

This document records findings from a deep scan of the RisuAI source code,
identifying every subsystem, data structure, and behavioral detail that the
`TavernKit::RisuAI` layer must implement for parity.

The existing `st-risuai-parity.md` already covers the high-level parity
checklist. This delta focuses on **precise implementation requirements** --
exact field lists, algorithm steps, edge cases, and line references from the
RisuAI source.

---

## Files Scanned

| File | Lines | Subsystem |
|------|-------|-----------|
| `src/ts/cbs.ts` | 2,480 | CBS macro engine (130+ registered functions) |
| `src/ts/parser.svelte.ts` | 1,875 | Message parser + CBS evaluation pipeline |
| `src/ts/process/lorebook.svelte.ts` | ~600 | Lorebook activation + decoration + budget |
| `src/ts/process/index.svelte.ts` | ~1,900 | Main chat processing pipeline (4 stages) |
| `src/ts/process/prompt.ts` | ~150 | Prompt item type definitions |
| `src/ts/process/templates/templates.ts` | ~200 | Template presets + position parser |
| `src/ts/process/scripts.ts` | ~400 | Regex script execution engine |
| `src/ts/process/triggers.ts` | ~800 | Trigger system v1 + v2 |
| `src/ts/storage/database.svelte.ts` | ~2,200 | Data model (character, loreBook, Chat, etc.) |
| `src/ts/characterCards.ts` | ~2,300 | Character card import/export |
| `src/ts/tokenizer.ts` | ~500 | 10 tokenizer types with LRU caching |
| `src/ts/plugins/` | ~400 | Plugin system V3 (sandboxed iframes) |
| `src/etc/docs/cbs_intro.cbs` | ~30 | CBS introduction documentation |
| `src/etc/docs/cbs_docs.cbs` | ~300 | Full CBS reference documentation |

---

## 1. CBS Macro Engine

### 1.1 Syntax Overview

CBS (Curly Braced Syntax) uses `{{...}}` delimiters with `::` argument
separators. Nesting is supported: `{{random::{{user}}::{{char}}}}`.

Block syntax: `{{#blocktype args}}...{{/blocktype}}` or `{{/}}` shorthand.

Comments: `{{// comment}}` (stripped), `{{comment::...}}` (displayed).

Math expression shorthand: `{{? 1 + 2 * 6}}` with standard operator precedence.

**Source:** `cbs.ts`, `parser.svelte.ts`

### 1.2 Block Types (10 total)

| Block | Status | Operators | Whitespace | Use |
|-------|--------|-----------|------------|-----|
| `#when` | Active | 13+ operators | trimmed (default), `keep`, `legacy` | Conditional with operators |
| `#if` | Deprecated | None | trimmed | Legacy conditional (truthy = `"1"` or `"true"`) |
| `#if_pure` | Deprecated | None | preserved | Legacy conditional + whitespace |
| `#each` | Active | `keep` | trimmed/kept | Array iteration |
| `#escape` | Active | `keep` | trimmed/kept | Raw text escaping |
| `#puredisplay` | Active | - | preserved | Raw display (replaces `#pure`) |
| `#pure` | Deprecated | - | preserved | Legacy raw display |
| `#func` | Active | - | preserved | Function definition |
| `#code` | Active | - | normalized | Escape sequence normalization |
| `:else` | Active | - | - | Conditional else clause |

**Implementation requirement:** All 10 block types must be supported for
backward compatibility, even deprecated ones.

### 1.3 #when Operator System (13+ operators)

The `#when` block supports rich conditional logic:

```
{{#when::A::is::B}}        String equality
{{#when::A::isnot::B}}     String inequality
{{#when::A::>::B}}         Numeric greater than (parseFloat)
{{#when::A::<::B}}         Numeric less than
{{#when::A::>=::B}}        Numeric >=
{{#when::A::<=::B}}        Numeric <=
{{#when::A::and::B}}       Both truthy
{{#when::A::or::B}}        At least one truthy
{{#when::not::A}}          Negate
{{#when::var::varname}}         Chat variable truthy
{{#when::varname::vis::literal}} Chat variable === literal
{{#when::varname::visnot::literal}} Chat variable !== literal
{{#when::toggle::name}}         Toggle enabled
{{#when::togglename::tis::literal}} Toggle === literal
{{#when::togglename::tisnot::literal}} Toggle !== literal
```

**Evaluation strategy:** Stack-based, right-to-left processing.

**Modifiers:** `keep` (preserve whitespace), `legacy` (old parsing mode).

**Truthiness:** `"1"` or `"true"` (case-insensitive) = truthy; all else = falsy.

**Source:** `parser.svelte.ts:1203-1422`, `cbs.ts:2380-2417`

### 1.4 #each Array Iteration

```
{{#each arrayName as itemVar}}
  {{slot::itemVar}}
{{/each}}
```

Supports:
- JSON arrays: `[1,2,3]`
- JSON objects: `{"key":"value"}`
- `§`-delimited strings: `a§b§c`
- `::keep` modifier for whitespace preservation

**Source:** `parser.svelte.ts:1441-1451` (start), `1744-1762` (iterator)

### 1.5 #func Function Definitions

```
{{#func myfunction arg1 arg2}}
  {{arg::0}} and {{arg::1}}
{{/func}}

{{call::myfunction::value1::value2}}
```

- Arguments accessed via `{{arg::0}}`, `{{arg::1}}`, etc.
- Functions scoped to current parse context
- Call stack limit: 20 recursive calls

**Source:** `parser.svelte.ts:1453-1457` (start), `1764-1770` (end), `1788-1805` (call)

### 1.6 #escape and #puredisplay

**#escape:** Converts `{`, `}`, `(`, `)` to Unicode escape equivalents
(`\uE9B8-\uE9BB`). No CBS parsing inside. `::keep` preserves whitespace.

**#puredisplay:** Displays content without CBS processing. Escapes inner
`{{` to `\\{\\{` and `}}` to `\\}\\}`.

**#code:** Normalizes escape sequences (`\n`, `\r`, `\t`, `\uXXXX`, etc.).
Removes all newlines and tabs first, then processes escape sequences.

### 1.7 Built-in Macros (130+ functions)

Organized by category:

| Category | Count | Key Examples |
|----------|-------|-------------|
| Character/User Data | 8 | `char`/`bot`, `user`, `personality`, `description`, `scenario`, `persona` |
| Chat History | 8 | `history`, `previouscharchat`, `previoususerchat`, `lorebook` |
| Time/Date | 10 | `date`, `time`, `unixtime`, `isotime`, `isodate`, `message_time` |
| System/Metadata | 14 | `chat_index`, `model`, `role`, `metadata`, `maxcontext`, `prefillsupported` |
| Variables | 8 | `getvar`, `setvar`, `addvar`, `setdefaultvar`, `getglobalvar`, `tempvar`, `settempvar`, `return` |
| Math/Random | 14 | `calc`, `round`, `floor`, `ceil`, `abs`, `randint`, `dice`, `random`, `roll`, `pick` |
| Strings | 11 | `length`, `lower`, `upper`, `capitalize`, `trim`, `replace`, `split`, `join` |
| Arrays | 10 | `arraylength`, `arrayelement`, `arraypush`, `arraypop`, `makearray`, `filter`, `range` |
| Objects/Dicts | 4 | `dictelement`, `element`, `makedict`, `object_assert` |
| Logic/Compare | 11 | `equal`, `not_equal`, `greater`, `less`, `and`, `or`, `not`, `all`, `any` |
| Unicode/Encoding | 7 | `unicode_encode`, `unicode_decode`, `hash`, `fromhex`, `tohex` |
| Media/Display | 13 | `asset`, `image`, `video`, `audio`, `emotion`, `bgm`, `bg` |
| Crypto | 3 | `xor`, `xordecrypt`, `crypt` |
| Modules | 3 | `module_enabled`, `module_assetlist`, `chardisplayasset` |
| Escape Characters | 10 | `bo`, `bc`, `decbo`, `decbc`, display-escaped brackets/angles/colon |
| Numeric Aggregates | 4 | `min`, `max`, `sum`, `average` |
| Misc | 15+ | `button`, `comment`, `tex`, `ruby`, `codeblock`, `bkspc`, `erase`, `file` |

**Total: 130+ built-in functions and operators**

**Aliases are extensive:** e.g., `char` aliased to `bot`; `previouscharchat`
aliased to `lastcharmessage`; `getvar` has no alias but `tempvar` aliased to
`gettempvar`.

**Registration API:**
```typescript
registerFunction({
  name: 'functionname',
  callback: (str, matcherArg, args, vars) => { ... },
  alias: ['alias1', 'alias2'],
  description: 'Human-readable description',
  deprecated?: { message, since?, replacement? },
  internalOnly?: boolean
})
```

**Source:** `cbs.ts:145-2356`

### 1.8 Variable System (4 scopes)

| Scope | Get | Set | Persistence |
|-------|-----|-----|-------------|
| Chat variables | `{{getvar::name}}` | `{{setvar::name::value}}` | Per-chat |
| Global variables | `{{getglobalvar::name}}` | (none in CBS) | Cross-chat |
| Temp variables | `{{tempvar::name}}` | `{{settempvar::name::value}}` | Per-parse cycle |
| Function args | `{{arg::0}}` | (defined by `#func`) | Per-function call |

Additional:
- `{{addvar::name::value}}` -- numeric addition to chat variable
- `{{setdefaultvar::name::value}}` -- set only if undefined
- `{{return::value}}` -- force return, stops parsing

**Default variables:** `character.defaultVariables` + `db.templateDefaultVariables`
(key=value per line, no trimming). Missing values fall back to `'null'`.

**Toggles:** Global variables with `toggle_` prefix. `#when::toggle::X` checks
`globalChatVariables['toggle_X']` for `'1'`/`'true'`.

**Source:** `cbs.ts:731-838`, `database.svelte.ts`

### 1.9 Math Expression Engine

`{{calc::expression}}` and `{{? expression}}` support:
- Operators: `+`, `-`, `*`, `/`, `^` (power), `%` (modulo)
- Standard precedence (PEMDAS)
- `fixnum` for decimal precision: `{{fixnum::3.14159::2}}` -> `3.14`

**Dice notation:** `{{dice::2d6}}` (roll N dM-sided dice, sum results)

**Deterministic variants:** `rollp`, `pick` use message index as seed.

**Source:** `cbs.ts:779-2089`

### 1.10 Evaluation Pipeline

1. Input: raw text with `{{...}}` and `{{#...}}...{{/...}}` blocks
2. Character-by-character scanning
3. Delimiter detection (`{{`, `}}`)
4. Block start/end markers identified
5. Nested processing via stack (512 elements, 20 call depth limit)
6. Variable substitution
7. Output: final string

**Processing modes (10):**

| Mode | Parsing | Whitespace | Trigger |
|------|---------|-----------|---------|
| `parse` | Yes | Trimmed | Default |
| `newif` | Yes | Trimmed | `#when` truthy branch |
| `keep` | Yes | Preserved | `#when::keep::`, `#each::keep::` |
| `legacy` | Yes | Legacy trim | `#when::legacy::` |
| `ignore` | No | N/A | Falsy `#when`/`#if` |
| `each` | Yes | Trimmed/kept | Array iteration |
| `pure` | No | Preserved | `#pure` (deprecated) |
| `pure-display` | No | Preserved | `#puredisplay` |
| `escape` | No | Trimmed/kept | `#escape` |
| `function` | No | Preserved | `#func` definition |

**Error handling:**
- Invalid blocks: returned as literal text
- Unclosed blocks: returned as-is
- Call stack overflow: `"ERROR: Call stack limit reached"`

**Source:** `parser.svelte.ts:1073-1848`

### 1.11 Metadata Macro

`{{metadata::key}}` provides runtime introspection:

- `mobile`, `local`, `node` -- platform booleans
- `version`, `major` -- version info
- `lang`, `browserlang` -- locale
- `modelshortname`, `modelname`, `modelformat`, `modelprovider`, `modeltokenizer`
- `risutype` -- platform type (node/web/tauri)
- `maxcontext` -- context window size

**Source:** `cbs.ts:1841-1925`

---

## 2. Lorebook System

### 2.1 Entry Data Structure

```typescript
interface loreBook {
    key: string                           // Primary keywords (comma-separated)
    secondkey: string                     // Secondary keywords
    insertorder: number                   // Priority/order (default: 100)
    comment: string                       // Display name
    content: string                       // Content with optional decorators
    mode: 'multiple'|'constant'|'normal'|'child'|'folder'
    alwaysActive: boolean                 // Always include without matching
    selective: boolean                    // Require both key AND secondkey
    extentions?: {
        risu_case_sensitive: boolean      // Case-sensitive matching
    }
    activationPercent?: number            // Legacy probability
    useRegex?: boolean                    // Regex patterns in keys
    bookVersion?: number
    id?: string                           // UUID
    folder?: string                       // Folder grouping
}
```

**Entry modes:**
- `normal` -- standard keyword matching
- `constant` -- always active (legacy, replaced by `alwaysActive`)
- `multiple` -- multiple related entries
- `child` -- linked to parent entry
- `folder` -- folder structure (key = `\uf000folder:<uuid>`)

**Source:** `database.svelte.ts`

### 2.2 Decorator System (30+ decorators)

All decorators parsed via `CCardLib.decorator.parse()` from the `content` field.

| Decorator | Args | Effect |
|-----------|------|--------|
| `@end` | none | Position = `'depth'`, depth = 0 |
| `@depth` | int | Set insertion depth in chat history |
| `@reverse_depth` | int | Set reverse insertion depth (from end) |
| `@role` | `'user'\|'assistant'\|'system'` | Set message role |
| `@position` | string | Set position: `'pt_*'`, `'after_desc'`, `'before_desc'`, `'personality'`, `'scenario'` |
| `@scan_depth` | int | Messages back to scan for keywords |
| `@priority` | int | Custom priority for budget sorting |
| `@activate` | none | Force activation regardless of keywords |
| `@dont_activate` | none | Force deactivation |
| `@activate_only_after` | int (msg count) | Deactivate if chat length < threshold |
| `@activate_only_every` | int (modulo) | Activate only when chatLength % N === 0 |
| `@is_greeting` | int | Only activate on specific greeting (fmIndex) |
| `@probability` | 0-100 | Random activation chance (percent) |
| `@additional_keys` | key1, key2, ... | Add extra search keywords |
| `@exclude_keys` | key1, key2, ... | Exclude if ANY keyword matches |
| `@exclude_keys_all` | key1, key2, ... | Exclude if ALL keywords match |
| `@match_full_word` | none | Enable full-word matching |
| `@match_partial_word` | none | Disable full-word matching (default) |
| `@recursive` | none | Enable recursive scanning for this entry |
| `@unrecursive` | none | Disable recursive scanning |
| `@no_recursive_search` | none | Don't search recursively activated content |
| `@keep_activate_after_match` | none | Persist activation via chat var `__internal_ka_<id>` |
| `@dont_activate_after_match` | none | Prevent re-activation via chat var `__internal_da_<id>` |
| `@inject_lore` | location (name) | Inject into another lore entry (append) |
| `@inject_at` | location | Inject at position (append) |
| `@inject_replace` | text | Inject with replace operation |
| `@inject_prepend` | text | Inject with prepend operation |
| `@ignore_on_max_context` | none | Priority = -1000 (lowest) |
| `@disable_ui_prompt` | `'post_history_instructions'\|'system_prompt'` | Hide UI prompts |
| `@instruct_depth` | int | **NOT IMPLEMENTED** in RisuAI |
| `@reverse_instruct_depth` | int | **NOT IMPLEMENTED** |
| `@instruct_scan_depth` | int | **NOT IMPLEMENTED** |
| `@is_user_icon` | none | **NOT IMPLEMENTED** |

**Implementation note:** Return `false` from decorator parsing = error/invalid.
Return `void` = success.

**Source:** `lorebook.svelte.ts:292-507`

### 2.3 Keyword Matching Algorithm

Function: `searchMatch(messages, { keys, searchDepth, regex, fullWordMatching, all?, dontSearchWhenRecursive })`

**Steps:**
1. Slice last `searchDepth` messages from chat history
2. Normalize keys: trim, filter empty strings
3. Flatten sources: original messages + recursively activated prompts
   (unless `dontSearchWhenRecursive`)
4. **Regex mode:** test each key as `/pattern/flags` against each message
5. **Text mode:**
   - Remove comments (`{{//...}}`) and metadata
   - Lowercase all text and keys
   - **Full-word:** split on spaces, exact match required
   - **Partial:** remove spaces, substring match
6. **All mode:** ALL keys must match; otherwise ANY key matches
7. Message format: `\x01{{username}}:` + message data

**Source:** `lorebook.svelte.ts:99-222`

### 2.4 Activation Loop

```
WHILE matching:
  FOR each lore entry:
    1. Skip if already activated
    2. Skip if mode='child' and parent not found/activated
    3. Parse decorators from content
    4. Check activation conditions:
       - @activate: force activate
       - @dont_activate: force deactivate
       - @activate_only_after: check message count
       - @activate_only_every: check modulo
       - @is_greeting: check fmIndex
       - @probability: random chance
    5. If not forced: search keywords
       - Primary + secondkey (if selective)
       - Additional keys from @additional_keys
       - Exclude keys from @exclude_keys/@exclude_keys_all
    6. If activated:
       a. Store metadata (depth, pos, prompt, role, order, tokens, priority)
       b. Set chat vars for @keep/@dont_activate_after_match
       c. If recursive: add content to recursivePrompt for next iteration
```

**Prevents infinite loops:** tracked via `activatedIndexes` set.

**Source:** `lorebook.svelte.ts:224-594`

### 2.5 Token Budget & Priority

1. Sort by `priority` descending (default priority = `insertorder`)
2. Filter by token budget (cumulative; stop when budget exceeded)
3. Separate `@inject_lore` entries
4. Apply injections to target lore entries
5. Re-sort by `insertorder` descending
6. Reverse for final output order

**`@ignore_on_max_context`** sets priority to -1000, ensuring these entries
are excluded first when budget is tight.

**Source:** `lorebook.svelte.ts:596-622`

### 2.6 Lore Sources

Combined in activation: `character.globalLore` + `chat.localLore` + module lorebooks.

**Per-character settings** (`loreSettings`):
- `tokenBudget` -- overrides DB `loreBookToken` (default: 800)
- `scanDepth` -- overrides DB `loreBookDepth` (default: 5)
- `recursiveScanning` -- boolean
- `fullWordMatching` -- boolean (optional)

**Source:** `database.svelte.ts`, `lorebook.svelte.ts`

### 2.7 Injection System

Lore entries can modify other entries via decorators:

- `@inject_lore <name>` -- append content to entry with matching `comment`
- `@inject_at <position>` -- append at named position
- `@inject_replace <text>` -- replace operation
- `@inject_prepend <text>` -- prepend operation

This enables modular lore composition where one entry augments another.

---

## 3. Prompt Assembly Pipeline

### 3.1 Template System

RisuAI uses `promptTemplate` -- an ordered list of typed cards:

```typescript
type PromptItem =
    PromptItemPlain |      // { type: 'plain'|'jailbreak'|'cot', type2, text, role }
    PromptItemTyped |      // { type: 'persona'|'description'|'lorebook'|'postEverything'|'memory', innerFormat? }
    PromptItemChat |       // { type: 'chat', rangeStart, rangeEnd }
    PromptItemAuthorNote | // { type: 'authornote', innerFormat?, defaultText? }
    PromptItemChatML |     // { type: 'chatML', text }
    PromptItemCache        // { type: 'cache', name, depth, role }
```

**Card types:**
- `plain` / `jailbreak` / `cot` -- text with role and sub-type (normal, globalNote, main)
- `persona` / `description` / `lorebook` / `postEverything` / `memory` -- typed slots with optional `innerFormat` wrapping via `{{slot}}`
- `chat` -- chat history slice (`rangeStart` to `rangeEnd`, negative = from end)
- `authornote` -- author's note with optional format and default text
- `chatML` -- raw ChatML format (`<|im_start|>role\n...<|im_end|>`)
- `cache` -- Anthropic prompt caching marker (depth, role filter)

### 3.2 Template Position Injection

Templates support `{{position::name}}` placeholders for dynamic injection:
- `pt_custom_name` -- custom position
- `before_desc`, `after_desc` -- relative to character description
- `personality`, `scenario` -- at specific prompt sections

Lore entries with `@position` decorator inject into these slots.

### 3.3 Four-Stage Pipeline

**Stage 1: Prompt Preparation** (index.svelte.ts:295-563)
- Load lorebooks, apply decorators
- Separate by position type (depth, description, etc.)
- Build `unformated` object with 10 categories:
  `main`, `jailbreak`, `chats`, `lorebook`, `globalNote`, `authorNote`,
  `lastChat`, `description`, `postEverything`, `personaPrompt`
- Apply position parser for custom injection points
- Tokenize all content

**Stage 2: Memory Integration** (index.svelte.ts:957-1043)
- Choose algorithm: HypaMemory V1/V2/V3, or SupaMemory
- Compress old messages into memory summaries
- Update token counts

**Stage 3: Final Formatting** (index.svelte.ts:1110-1385)
- Apply promptTemplate ordering (or legacy formatting order)
- Process special prompt types
- Apply position parser
- Merge system messages (GPT/Claude models)
- Token recheck: remove removable entries if over budget
- Apply Lua edit triggers

**Stage 4: API Request & Response** (index.svelte.ts:1439-1936)
- Send formatted prompt to API
- Handle streaming/non-streaming responses
- Process response scripts/formatting
- Emotion detection, asset handling
- Auto-continue if needed

### 3.4 Internal Message Format

```typescript
interface OpenAIChat {
    role: 'system' | 'user' | 'assistant' | 'function'
    content: string
    memo?: string               // Internal tracking ID
    name?: string               // Character/user name
    removable?: boolean         // Can be trimmed for budget
    attr?: string[]             // e.g., 'nameAdded'
    multimodals?: MultiModal[]  // Images/audio/video
    thoughts?: string[]         // Chain-of-thought content
    cachePoint?: boolean        // Anthropic cache marker
}
```

### 3.5 ST Preset Import

RisuAI can convert SillyTavern preset JSON into its template cards via
`stChatConvert()`. Maps ST identifiers to RisuAI types:

| ST Identifier | RisuAI Type |
|---------------|-------------|
| `main` | `{ type: 'plain', type2: 'main' }` |
| `jailbreak` / `nsfw` | `{ type: 'jailbreak' }` |
| `chatHistory` | `{ type: 'chat', rangeEnd: 'end' }` |
| `worldInfoBefore` | `{ type: 'lorebook' }` |
| `charDescription` | `{ type: 'description' }` |
| `personaDescription` | `{ type: 'persona' }` |
| `assistant_prefill` | `{ type: 'postEverything' }` + bot-role plain |

**Source:** `database.svelte.ts:2172-2276`

### 3.6 Prebuilt Presets

Default NAI template example:
```
chat[0:-6] → main prompt → chat[-6:-4] → persona → lorebook →
description → globalNote → separator("***") → authornote → chat[-4:end]
```

---

## 4. Regex Scripts

### 4.1 Data Structure

```typescript
interface customscript {
    comment: string      // User description
    in: string          // Regex pattern (no slashes/flags)
    out: string         // Replacement (CBS syntax, $1/$2/$&)
    type: string        // Execution mode
    flag?: string       // Regex + action flags
    ableFlag?: boolean  // Whether flags enabled
}
```

### 4.2 Execution Types (6)

| Type | When | Modifies |
|------|------|----------|
| `modify input` | User inputs message | Actual message data |
| `modify output` | AI outputs message | Actual message data |
| `Modify Request Data` | Before API request | Request payload |
| `Modify Display` | Before display | Display only (not data) |
| `Edit Translation Display` | Translation display | Translation only |
| `Disabled` | Never | N/A |

### 4.3 Flag System

Standard regex flags: `g`, `i`, `m`, `s`, `u`

Custom directives in `<...>`:
- `<order N>` -- execution priority (higher = first)
- `<cbs>` -- parse IN field as CBS before regex matching
- `<move_top>` -- output appended to start of string
- `<move_bottom>` -- output appended to end of string
- `<repeat_back>` -- repeat previous match result (supports `end`, `start`, `end_nl`, `start_nl`)
- `<inject>` -- inject matched text into message history (removes from display)
- `<no_end_nl>` -- don't auto-add newline at end

### 4.4 Special Directives

Output patterns starting with `@@`:
- `@@emo {emotion_name}` -- trigger emotion state change
- `@@inject` -- store in message history
- `@@move_top` / `@@move_bottom` -- positional replacement
- `@@repeat_back {position}` -- repeat last match

### 4.5 Script Sources & Ordering

Collected from: `db.presetRegex` -> `character.customscript` -> module scripts

Scripts ordered by `<order N>` directive (descending).

CBS runs **before** regex scripts in the processing pipeline.

Cache: LRU with 1000-entry limit (key = scripts+data hash).

**Source:** `scripts.ts`, `lorebook.svelte.ts`

---

## 5. Trigger System

### 5.1 Data Structure

```typescript
interface triggerscript {
    comment: string
    type: 'start'|'manual'|'output'|'input'|'display'|'request'
    conditions: triggerCondition[]
    effect: triggerEffect[]
    lowLevelAccess?: boolean
}
```

### 5.2 Trigger Types (6)

- `start` -- character/chat initialization
- `manual` -- user-triggered via `risu-trigger` attribute
- `output` -- after AI response
- `input` -- when user submits
- `display` -- before displaying (read-only)
- `request` -- before API request

### 5.3 Condition Types

**Variable condition:**
```typescript
{ type: 'var'|'value', var: string, value: string,
  operator: '='|'!='|'>'|'<'|'>='|'<='|'null'|'true' }
```

**Existence condition:**
```typescript
{ type: 'exists', value: string,
  type2: 'strict'|'loose'|'regex', depth: number }
```

**Chat index condition:**
```typescript
{ type: 'chatindex', value: string,
  operator: '='|'!='|'>'|'<'|'>='|'<='|'null'|'true' }
```

### 5.4 V1 Effects (16 types)

- `setvar` -- set trigger variable
- `cutchat` -- truncate chat messages
- `modifychat` -- edit specific message
- `systemprompt` -- add system prompt (location: start/historyend/promptend)
- `impersonate` -- simulate role (user/char)
- `command` -- execute multi-command
- `stop` -- halt execution
- `runtrigger` -- chain another trigger
- `showAlert` -- display alert
- `extractRegex` -- regex extraction
- `runLLM` -- call AI model
- `checkSimilarity` -- vector similarity
- `sendAIprompt` -- send to AI
- `runImgGen` -- image generation
- `triggercode` / `triggerlua` -- custom code

**`lowLevelAccess` gates:** alerts, LLM, regex extract, img gen, send AI prompt.

### 5.5 V2 Effects (60+ types)

Structured block-based format with control flow:

**Control flow:**
- `v2If`, `v2Else`, `v2EndIndent`, `v2Loop`, `v2LoopNTimes`, `v2BreakLoop`

**Variables:**
- `v2SetVar`, `v2MakeArrayVar`, `v2MakeDictVar`

**String operations (8):**
- `v2ToLowerCase`, `v2ToUpperCase`, `v2SplitString`, `v2JoinArrayVar`,
  `v2ReplaceString`, `v2GetCharAt`, `v2SetCharAt`, `v2ConcatString`

**Array operations (11):**
- `v2GetArrayVar`, `v2SetArrayVar`, `v2PushArrayVar`, `v2PopArrayVar`,
  `v2ShiftArrayVar`, `v2UnshiftArrayVar`, `v2SpliceArrayVar`,
  `v2SliceArrayVar`, `v2GetIndexOfValueInArrayVar`,
  `v2RemoveIndexFromArrayVar`

**Dict operations (8):**
- `v2GetDictVar`, `v2SetDictVar`, `v2DeleteDictKey`, `v2HasDictKey`,
  `v2ClearDict`, `v2GetDictKeys`, `v2GetDictValues`, `v2GetDictSize`

**Chat operations (7):**
- `v2GetLastMessage`, `v2GetFirstMessage`, `v2GetMessageAtIndex`,
  `v2GetMessageCount`, `v2CutChat`, `v2ModifyChat`, `v2UpdateChatAt`,
  `v2QuickSearchChat`

**Lorebook CRUD (9):**
- `v2ModifyLorebook`, `v2GetLorebook`, `v2GetLorebookCount`,
  `v2GetLorebookEntry`, `v2SetLorebookActivation`,
  `v2GetLorebookIndexViaName`, `v2CreateLorebook`,
  `v2ModifyLorebookByIndex`, `v2DeleteLorebookByIndex`,
  `v2SetLorebookAlwaysActive`

**Character operations (4):**
- `v2GetCharacterDesc`, `v2SetCharacterDesc`,
  `v2GetPersonaDesc`, `v2SetPersonaDesc`

**System/Request:**
- `v2SystemPrompt`, `v2GetRequestState`, `v2GetRequestStateRole`,
  `v2GetRequestStateLength`

**UI/Display:**
- `v2GetDisplayState`, `v2SetDisplayState`, `v2UpdateGUI`,
  `v2GetAlertInput`, `v2GetAlertSelect`

**Other:**
- `v2Impersonate`, `v2Command`, `v2SendAIprompt`, `v2ImgGen`,
  `v2CheckSimilarity`, `v2RunLLM`, `v2ShowAlert`, `v2ExtractRegex`,
  `v2Tokenize`, `v2RegexTest`, `v2Calculate`, `v2Random`,
  `v2ConsoleLog`, `v2Wait`

### 5.6 V2 Control Flow

V2 uses indent-based control flow:
- Indent level tracks nesting
- `v2If` / `v2Else` / `v2EndIndent` form blocks
- `v2Loop` / `v2LoopNTimes` / `v2BreakLoop` for iteration
- Local variables (`v2DeclareLocalVar`) scoped by indent

**Extra V2 conditions:** `∈`, `∋`, `∉`, `∌`, `≒`, `≡` (set/contains/approx/equiv)

**Safety:**
- Recursion limited to 10 unless `lowLevelAccess`
- `display` and `request` modes restrict allowed effect types

**Source:** `triggers.ts`

---

## 6. Character Cards

### 6.1 Supported Import Formats

- **CharacterCardV3** (CCv3) -- latest spec from `@risuai/ccardlib`
- **CharacterCardV2Risu** (CCv2) -- RisuAI variant
- **OldTavernChar** -- legacy format
- **CharX format** (`.charx`, `.jpg/.jpeg`) -- packaged with metadata

### 6.2 Character Data Structure

```typescript
interface character {
    type?: "character"
    name: string
    image?: string                      // Base64 or file path
    firstMessage: string               // Initial greeting
    desc: string                       // Description/persona
    notes: string                      // System notes
    chats: Chat[]                      // Chat history
    chatFolders: ChatFolder[]
    chatPage: number                   // Current chat index
    viewScreen: 'emotion'|'none'|'imggen'
    bias: [string, number][]           // Token bias overrides
    emotionImages: [string, string][]  // Emotion -> image mapping
    globalLore: loreBook[]             // World info entries
    chaId: string                      // Unique ID
    sdData: [string, string][]         // SD generation data
    customscript: customscript[]       // Regex scripts
    triggerscript: triggerscript[]     // Triggers
    utilityBot: boolean               // Utility vs roleplay mode
    // ... 30+ additional fields
}
```

### 6.3 Field Mapping

| RisuAI | CCv2 | CCv3 | Legacy |
|--------|------|------|--------|
| `name` | `char_name` | `name` | `char_name`/`name` |
| `desc` | `char_persona` | `description` | `char_persona`/`description` |
| `firstMessage` | `char_greeting` | `first_mes` | `char_greeting`/`first_mes` |
| `personality` | (derived) | `personality` | (custom) |
| `scenario` | (custom) | `scenario` | (custom) |
| `exampleMessage` | (custom) | `mes_example` | (custom) |
| `globalLore` | `world_scenario` | `lorebook` | (custom) |

### 6.4 Import Process

1. File detection (JSON, CharX, image)
2. Format identification (CCv3 > CCv2 > legacy)
3. Conversion via `convertOffSpecCards()`
4. Module extraction from CharX
5. Lorebook extraction
6. Image/asset processing

**PNG metadata:** Writer strips existing `tEXt` chunks for `chara`/`ccv3`,
writes new data. Import prefers `ccv3`, falls back to `chara`/legacy.
Embedded assets use `tEXt` keys `chara-ext-asset_...`.

**Source:** `characterCards.ts`

---

## 7. Tokenizer System

### 7.1 Supported Types (10)

| ID | Name | Backend |
|----|------|---------|
| `tik` | Tiktoken (OpenAI) | `cl100k_base`, `o200k_base` |
| `mistral` | Mistral | Custom |
| `novelai` | NovelAI | SentencePiece |
| `claude` | Claude | Claude tokenizer |
| `llama` | Llama | SentencePiece |
| `llama3` | Llama3 | JSON tokenizer |
| `novellist` | Novellist | SentencePiece |
| `gemma` | Gemma | SentencePiece |
| `cohere` | Cohere | JSON tokenizer |
| `deepseek` | DeepSeek | JSON tokenizer |

### 7.2 API

```typescript
// Main encoding
encode(data: string): Promise<number[] | Uint32Array | Int32Array>
tokenize(data: string): Promise<number>

// Accurate with CBS parsing
tokenizeAccurate(data: string, consistantChar?: boolean): Promise<number>

// Chat-based
class ChatTokenizer {
    tokenizeChat(data: OpenAIChat): Promise<number>
    tokenizeChats(data: OpenAIChat[]): Promise<number>
    tokenizeMultiModal(data: MultiModal): Promise<number>
}
```

### 7.3 Caching

LRU cache (max 1500 entries). Key: `data + aiModel + customTokenizer +
provider + googleClaudeTokenizing + modelTokenizer + pluginTokenizer`.

### 7.4 Budget Management

- **Persistent tokens:** description, personality, scenario, global lorebooks
- **Dynamic tokens:** chat-specific lorebooks
- **Multimodal:** GPT vision quality scaling (87 low, 256+ high)

**Source:** `tokenizer.ts`

---

## 8. Memory Systems

### 8.1 Algorithms

| Algorithm | Setting | Description |
|-----------|---------|-------------|
| HypaMemory V1 | `db.hanuraiEnable` | Original memory compression |
| HypaMemory V2 | `db.hypav2` | Improved compression |
| HypaMemory V3 | `db.hypaV3` | Latest (recommended) |
| SupaMemory | (default) | Default memory system |

### 8.2 Integration

Memory is processed in Stage 2 of the pipeline. Compressed data stored in
`Chat.supaMemoryData`, `Chat.hypaV2Data`, or `Chat.hypaV3Data`.

When memory is enabled, old messages are compressed into summaries that fit
within the token budget. The `memory` prompt item type places the compressed
content into the prompt template.

---

## 9. Plugin System

### 9.1 API Version: V3

Plugins run in sandboxed iframes with message-passing API.

**Hooks:**
- `editinput` -- process user input
- `editoutput` -- process AI output
- `editprocess` -- process request data
- `editdisplay` -- process display rendering

Hook signature: `(data: string) => string | null`

### 9.2 Capabilities

- `SafeElement` DOM manipulation (x- prefix attributes only)
- Read-only database access via callbacks
- Menu system: `additionalChatMenu`, `additionalFloatingActionButtons`,
  `additionalHamburgerMenu`, `additionalSettingsMenu`
- Custom provider integration via `currentPluginProvider`
- Plugin tokenizer override

### 9.3 Limitations

- Only serializable data (string, number, boolean, null, array, object)
- No direct database modifications
- Security sandboxing prevents script injection

---

## 10. Lua/Script Engine

### 10.1 Engines

- Lua (wasmoon) -- primary scripting engine
- Python (pyodide) -- optional secondary engine

### 10.2 Hook Modes

- `onInput`, `onOutput`, `onStart`, `onButtonClick`, `callListenMain`
- `editInput`, `editOutput`, `editDisplay`, `editRequest` pipelines

### 10.3 Access Control

- `ScriptingSafeIds` -- safe operations (chat read, var get/set, alerts)
- `ScriptingLowLevelIds` -- risky APIs (chat mutation, LLM requests, image gen)
- Access via generated access keys per execution context

### 10.4 Exposed APIs

Chat mutation (cut/insert/remove), variable get/set, alert dialogs,
prompt/token helpers, lorebook access, image generation, LLM requests.

---

## 11. Message Processing Pipeline (Full Flow)

```
User input
  ↓
Lua edit triggers (if configured)
  ↓
Plugin V2 hooks (scriptMode: editinput)
  ↓
Regex scripts (modify input)
  ↓
CBS parser ({{macro}} substitution)
  ↓
AI request (Stage 3-4 of prompt pipeline)
  ↓
AI response
  ↓
Triggers (output type)
  ↓
Regex scripts (modify output)
  ↓
Plugin hooks (editoutput)
  ↓
Display processing:
  - Plugin hooks (editdisplay)
  - Triggers (display type)
  - ParseMarkdown (syntax rendering)
  - Asset substitution (emotion/image/audio/video)
  - LaTeX/KaTeX rendering
  - Thought/Tool tag processing (<Thoughts>, <tool_call>)
  - DOMPurify sanitization
  ↓
User display
```

### 11.1 Asset Regex Pattern

```
{{(raw|path|img|image|video|audio|bgm|bg|emotion|asset|video-img|source)::(.+?)}}
```

### 11.2 Hidden Metadata

AI watermarking via zero-width Unicode characters.
Format: `{aigen|risuai|modelshortname}` encoded in base-6 zero-width chars.

---

## 12. Modules (.risum)

Module bundles include:
- Lorebook entries
- Regex scripts
- Triggers
- Assets
- Toggle definitions

Import/export uses rpack + asset payloads.

---

## 13. Database Settings (Lorebook-relevant)

| Setting | Type | Default | Purpose |
|---------|------|---------|---------|
| `loreBookDepth` | number | 5 | Messages back to scan |
| `loreBookToken` | number | 800 | Max tokens for all lore |
| `localActivationInGlobalLorebook` | boolean | false | Local lore activates global |

---

## 14. Deltas from Existing Parity Doc

The existing `st-risuai-parity.md` correctly covers the high-level structure.
This scan reveals the following **new or expanded details** not previously
documented:

### 14.1 CBS Engine -- New Detail

- **Function definitions** (`#func`/`call`) with call stack limit (20)
- **10 processing modes** with distinct whitespace/parsing behavior
- **§-delimited arrays** as alternative to JSON arrays
- **Deterministic RNG** (`rollp`/`pick`) seeded by message index
- **Crypto macros** (`xor`, `xordecrypt`, `crypt`)
- **Metadata introspection** (`{{metadata::key}}` with 15+ keys)
- **Unicode encode/decode** and hash operations
- **Display escape characters** (10 escape macros for literal bracket rendering)
- **`{{bkspc}}` and `{{erase}}`** for post-processing text manipulation

### 14.2 Lorebook -- New Detail

- **`@is_greeting` decorator** -- activate only on specific greeting index
- **`@ignore_on_max_context`** -- priority = -1000 for budget-constrained removal
- **`@instruct_depth`/`@reverse_instruct_depth`/`@instruct_scan_depth`** --
  defined but NOT IMPLEMENTED in RisuAI (stub only)
- **Activation loop is iterative** (while loop, not single-pass) to support
  recursive activation chains
- **Injection graph** -- entries can inject into each other via 4 operations
  (append, prepend, replace, inject_at)
- **Message format** for keyword search: `\x01{{username}}:` prefix

### 14.3 Prompt Assembly -- New Detail

- **`PromptItemCache`** type for Anthropic prompt caching (depth, role filter)
- **`PromptItemChatML`** for raw ChatML insertion
- **`postEverything`** auto-appended if missing from template
- **`utilityBot`** mode bypasses normal prompt unless `promptSettings.utilOverride`
- **`chatAsOriginalOnSystem`** flag in chat items (convert to system role)
- **Memory inner format** wrapping via `innerFormat` + `{{slot}}`

### 14.4 Regex Scripts -- New Detail

- **`<repeat_back>` directive** with 4 position modes (end/start/end_nl/start_nl)
- **`<no_end_nl>` directive** prevents auto-newline after HTML output
- **Output ending with `>`** auto-appends newline unless no_end_nl

### 14.5 Triggers -- New Detail

- **V2 extra conditions:** `∈`, `∋`, `∉`, `∌`, `≒`, `≡`
- **V2 local variables** (`v2DeclareLocalVar`) scoped by indent level
- **60+ V2 effects** (previously noted as "scripted" without full enumeration)
- **Lorebook CRUD from triggers** (9 operations: create, modify, delete, get, etc.)
- **Request state inspection** (`v2GetRequestState*` family)
- **UI state management** (`v2GetDisplayState`/`v2SetDisplayState`/`v2UpdateGUI`)
- **User interaction** from triggers (`v2GetAlertInput`/`v2GetAlertSelect`)

### 14.6 Character Cards -- New Detail

- **`bias` field** -- `[string, number][]` for token bias overrides
- **`emotionImages`** -- `[string, string][]` emotion-to-image mapping
- **`sdData`** / `newGenData` -- SD/image generation configuration
- **`viewScreen`** -- display mode selection (emotion/none/imggen)
- **Module extraction** from CharX format during import

### 14.7 Plugin System -- New Detail

- **V3 API** with sandboxed iframes (not previously enumerated)
- **`SafeElement`** DOM class with x- prefix attribute restriction
- **4 script hooks** (editinput/editoutput/editprocess/editdisplay)
- **Provider integration** -- plugins can override tokenizer and provider

### 14.8 Tokenizer -- New Detail

- **10 tokenizer types** (full list not previously enumerated)
- **LRU cache** (1500 entries) with composite key
- **`strongBan()` API** for biasing token IDs with case-variant handling
- **Google Cloud integration** for direct Gemini token counting

---

## Reference

- Parity checklist: `lib/tavern_kit/docs/notes/st-risuai-parity.md`
- ST alignment delta: `lib/tavern_kit/docs/compatibility/sillytavern-deltas.md`
