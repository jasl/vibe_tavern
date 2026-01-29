# RisuAI Compatibility Matrix

Reference: RisuAI source (`resources/Risuai/src/`)
TavernKit Layer: `TavernKit::RisuAI`

This matrix tracks TavernKit's implementation status against RisuAI features.
Use this document both as:
1. **Behavior documentation** - understanding RisuAI/TavernKit differences
2. **Implementation TODO list** - tracking feature completion (Wave 5)

Status legend:
- ✅ Implemented
- 🔨 In progress
- ❌ Not started
- ⏸️ Deferred
- 🚫 Intentional divergence

---

## 1. CBS Macro Engine

### 1.1 Syntax

| Feature | RisuAI | TavernKit | Wave |
|---------|--------|-----------|------|
| `{{...}}` delimiter | ✅ | ❌ | 5 |
| `::` argument separator | ✅ | ❌ | 5 |
| Nested macros | ✅ | ❌ | 5 |
| `{{#block}}...{{/block}}` syntax | ✅ | ❌ | 5 |
| `{{/}}` shorthand closing | ✅ | ❌ | 5 |
| `{{// comment}}` | ✅ | ❌ | 5 |
| `{{? expr}}` math shorthand | ✅ | ❌ | 5 |
| `§`-delimited arrays | ✅ | ❌ | 5 |

### 1.2 Block Types (10 total)

| Block | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `#when` | ✅ | ❌ | Active: conditional with operators |
| `#if` | ✅ | ❌ | Deprecated: legacy conditional |
| `#if_pure` | ✅ | ❌ | Deprecated: conditional + whitespace |
| `#each` | ✅ | ❌ | Active: array iteration |
| `#escape` | ✅ | ❌ | Active: raw text escaping |
| `#puredisplay` | ✅ | ❌ | Active: raw display |
| `#pure` | ✅ | ❌ | Deprecated: legacy raw display |
| `#func` | ✅ | ❌ | Active: function definition |
| `#code` | ✅ | ❌ | Active: escape sequence normalization |
| `:else` | ✅ | ❌ | Active: else clause |

### 1.3 #when Operators (13+)

| Operator | RisuAI | TavernKit | Meaning |
|----------|--------|-----------|---------|
| `is` | ✅ | ❌ | String equality |
| `isnot` | ✅ | ❌ | String inequality |
| `>` | ✅ | ❌ | Numeric greater than |
| `<` | ✅ | ❌ | Numeric less than |
| `>=` | ✅ | ❌ | Numeric >= |
| `<=` | ✅ | ❌ | Numeric <= |
| `and` | ✅ | ❌ | Both truthy |
| `or` | ✅ | ❌ | At least one truthy |
| `not` | ✅ | ❌ | Negate |
| `var` | ✅ | ❌ | Chat variable truthy |
| `vis` | ✅ | ❌ | Chat variable === literal |
| `visnot` | ✅ | ❌ | Chat variable !== literal |
| `toggle` | ✅ | ❌ | Toggle enabled |
| `tis` | ✅ | ❌ | Toggle === literal |
| `tisnot` | ✅ | ❌ | Toggle !== literal |

### 1.4 #when Modifiers

| Modifier | RisuAI | TavernKit | Effect |
|----------|--------|-----------|--------|
| `keep` | ✅ | ❌ | Preserve whitespace |
| `legacy` | ✅ | ❌ | Old parsing mode |

### 1.5 Built-in Macros (130+ total)

#### Character/User Data (8)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `char` / `bot` | ✅ | ❌ | Character name |
| `user` | ✅ | ❌ | User name |
| `personality` | ✅ | ❌ | Character personality |
| `description` | ✅ | ❌ | Character description |
| `scenario` | ✅ | ❌ | Scenario text |
| `persona` | ✅ | ❌ | User persona |
| `firstmessage` | ✅ | ❌ | First greeting |
| `example_message` | ✅ | ❌ | Example dialogue |

#### Chat History (8)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `history` | ✅ | ❌ | Full chat history |
| `previouscharchat` | ✅ | ❌ | Last char message |
| `previoususerchat` | ✅ | ❌ | Last user message |
| `lorebook` | ✅ | ❌ | Active lore entries |
| `lastcharmessage` | ✅ | ❌ | Alias: previouscharchat |
| `lastusermessage` | ✅ | ❌ | Alias: previoususerchat |
| `message_count` | ✅ | ❌ | Chat message count |
| `chat_index` | ✅ | ❌ | Current chat index |

#### Time/Date (10)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `date` | ✅ | ❌ | Current date |
| `time` | ✅ | ❌ | Current time |
| `unixtime` | ✅ | ❌ | Unix timestamp |
| `isotime` | ✅ | ❌ | ISO time |
| `isodate` | ✅ | ❌ | ISO date |
| `message_time` | ✅ | ❌ | Message timestamp |
| `weekday` | ✅ | ❌ | Day of week |
| `month` | ✅ | ❌ | Month name |
| `year` | ✅ | ❌ | Current year |
| `datetimeformat` | ✅ | ❌ | Custom format |

#### System/Metadata (14)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `chat_index` | ✅ | ❌ | Current chat index |
| `model` | ✅ | ❌ | Model name |
| `role` | ✅ | ❌ | Current role |
| `metadata` | ✅ | ❌ | 15+ keys introspection |
| `maxcontext` | ✅ | ❌ | Context window size |
| `prefillsupported` | ✅ | ❌ | Prefill capability |
| `is_mobile` | ✅ | ❌ | Mobile platform |
| `is_local` | ✅ | ❌ | Local mode |
| `version` | ✅ | ❌ | RisuAI version |
| `major` | ✅ | ❌ | Major version |
| `lang` | ✅ | ❌ | UI language |
| `browserlang` | ✅ | ❌ | Browser language |
| `risutype` | ✅ | ❌ | Platform type |
| `modeltokenizer` | ✅ | ❌ | Tokenizer name |

#### Variables (8)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `getvar` | ✅ | ❌ | Get chat variable |
| `setvar` | ✅ | ❌ | Set chat variable |
| `addvar` | ✅ | ❌ | Add to variable |
| `setdefaultvar` | ✅ | ❌ | Set if undefined |
| `getglobalvar` | ✅ | ❌ | Get global (read-only in CBS) |
| `tempvar` / `gettempvar` | ✅ | ❌ | Get temp variable |
| `settempvar` | ✅ | ❌ | Set temp variable |
| `return` | ✅ | ❌ | Force return value |

#### Math/Random (14)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `calc` | ✅ | ❌ | Expression evaluation |
| `round` | ✅ | ❌ | Round number |
| `floor` | ✅ | ❌ | Floor number |
| `ceil` | ✅ | ❌ | Ceiling number |
| `abs` | ✅ | ❌ | Absolute value |
| `fixnum` | ✅ | ❌ | Decimal precision |
| `randint` | ✅ | ❌ | Random integer |
| `dice` | ✅ | ❌ | Dice notation (NdM) |
| `random` | ✅ | ❌ | Random from list |
| `roll` | ✅ | ❌ | Non-deterministic |
| `rollp` | ✅ | ❌ | Deterministic (msg seed) |
| `pick` | ✅ | ❌ | Deterministic pick |
| `min` / `max` | ✅ | ❌ | Numeric min/max |
| `sum` / `average` | ✅ | ❌ | Aggregates |

#### Strings (11)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `length` | ✅ | ❌ | String length |
| `lower` | ✅ | ❌ | Lowercase |
| `upper` | ✅ | ❌ | Uppercase |
| `capitalize` | ✅ | ❌ | Capitalize |
| `trim` | ✅ | ❌ | Trim whitespace |
| `replace` | ✅ | ❌ | String replace |
| `split` | ✅ | ❌ | Split to array |
| `join` | ✅ | ❌ | Join array |
| `substring` | ✅ | ❌ | Substring |
| `indexof` | ✅ | ❌ | Find index |
| `contains` | ✅ | ❌ | Contains check |

#### Arrays (10)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `arraylength` | ✅ | ❌ | Array length |
| `arrayelement` | ✅ | ❌ | Get element |
| `arraypush` | ✅ | ❌ | Push element |
| `arraypop` | ✅ | ❌ | Pop element |
| `makearray` | ✅ | ❌ | Create array |
| `filter` | ✅ | ❌ | Filter array |
| `range` | ✅ | ❌ | Create range |
| `arrayslice` | ✅ | ❌ | Slice array |
| `arraysort` | ✅ | ❌ | Sort array |
| `arrayreverse` | ✅ | ❌ | Reverse array |

#### Objects/Dicts (4)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `dictelement` | ✅ | ❌ | Get dict value |
| `element` | ✅ | ❌ | Generic element access |
| `makedict` | ✅ | ❌ | Create dict |
| `object_assert` | ✅ | ❌ | Assert object structure |

#### Logic/Compare (11)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `equal` | ✅ | ❌ | Equality |
| `not_equal` | ✅ | ❌ | Inequality |
| `greater` | ✅ | ❌ | > comparison |
| `less` | ✅ | ❌ | < comparison |
| `and` | ✅ | ❌ | Logical AND |
| `or` | ✅ | ❌ | Logical OR |
| `not` | ✅ | ❌ | Logical NOT |
| `all` | ✅ | ❌ | All truthy |
| `any` | ✅ | ❌ | Any truthy |
| `true` / `false` | ✅ | ❌ | Boolean literals |
| `if_then_else` | ✅ | ❌ | Ternary |

#### Unicode/Encoding (7)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `unicode_encode` | ✅ | ❌ | To unicode |
| `unicode_decode` | ✅ | ❌ | From unicode |
| `hash` | ✅ | ❌ | Hash string |
| `fromhex` | ✅ | ❌ | From hex |
| `tohex` | ✅ | ❌ | To hex |
| `base64_encode` | ✅ | ❌ | To base64 |
| `base64_decode` | ✅ | ❌ | From base64 |

#### Media/Display (13)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `asset` | ✅ | ❌ | Asset reference |
| `image` | ✅ | ❌ | Image tag |
| `video` | ✅ | ❌ | Video tag |
| `audio` | ✅ | ❌ | Audio tag |
| `emotion` | ✅ | ❌ | Emotion trigger |
| `bgm` | ✅ | ❌ | Background music |
| `bg` | ✅ | ❌ | Background image |
| `raw` | ✅ | ❌ | Raw file path |
| `path` | ✅ | ❌ | Resolved path |
| `source` | ✅ | ❌ | Source tag |
| `video-img` | ✅ | ❌ | Video as image |
| `chardisplayasset` | ✅ | ❌ | Character display |
| `emotionlist` | ✅ | ❌ | Available emotions |

#### Crypto (3)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `xor` | ✅ | ❌ | XOR encrypt |
| `xordecrypt` | ✅ | ❌ | XOR decrypt |
| `crypt` | ✅ | ❌ | Encrypt/decrypt |

#### Modules (3)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `module_enabled` | ✅ | ❌ | Check module |
| `module_assetlist` | ✅ | ❌ | Module assets |
| `module_count` | ✅ | ❌ | Module count |

#### Escape Characters (10)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `bo` / `bc` | ✅ | ❌ | Brackets `{`/`}` |
| `decbo` / `decbc` | ✅ | ❌ | Display `{{`/`}}` |
| `lb` / `rb` | ✅ | ❌ | Angle `<`/`>` |
| `colon` | ✅ | ❌ | Double colon |
| `newline` | ✅ | ❌ | Newline char |
| `tab` | ✅ | ❌ | Tab char |
| `space` | ✅ | ❌ | Non-breaking space |

#### Misc (15+)

| Macro | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `button` | ✅ | ❌ | Interactive button |
| `comment` | ✅ | ❌ | Visible comment |
| `tex` | ✅ | ❌ | LaTeX rendering |
| `ruby` | ✅ | ❌ | Ruby annotation |
| `codeblock` | ✅ | ❌ | Code formatting |
| `bkspc` | ✅ | ❌ | Backspace char |
| `erase` | ✅ | ❌ | Erase content |
| `file` | ✅ | ❌ | File reference |
| `call` | ✅ | ❌ | Call function |
| `arg` | ✅ | ❌ | Function argument |
| `slot` | ✅ | ❌ | #each slot |
| `noop` | ✅ | ❌ | No operation |
| `json_stringify` | ✅ | ❌ | JSON encode |
| `json_parse` | ✅ | ❌ | JSON decode |
| `regex_test` | ✅ | ❌ | Regex match |

### 1.6 Variable Scopes (4)

| Scope | RisuAI | TavernKit | Persistence |
|-------|--------|-----------|-------------|
| Chat variables | ✅ | ❌ | Per-chat |
| Global variables | ✅ | ❌ | Cross-chat |
| Temp variables | ✅ | ❌ | Per-parse cycle |
| Function args | ✅ | ❌ | Per-function call |

### 1.7 Processing Modes (10)

| Mode | RisuAI | TavernKit | Trigger |
|------|--------|-----------|---------|
| `parse` | ✅ | ❌ | Default |
| `newif` | ✅ | ❌ | #when truthy |
| `keep` | ✅ | ❌ | ::keep modifier |
| `legacy` | ✅ | ❌ | ::legacy modifier |
| `ignore` | ✅ | ❌ | Falsy branch |
| `each` | ✅ | ❌ | Array iteration |
| `pure` | ✅ | ❌ | #pure (deprecated) |
| `pure-display` | ✅ | ❌ | #puredisplay |
| `escape` | ✅ | ❌ | #escape |
| `function` | ✅ | ❌ | #func definition |

### 1.8 Engine Features

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| 512-element stack | ✅ | ❌ | Processing stack |
| 20-depth call limit | ✅ | ❌ | Function calls |
| Deterministic RNG (msg index seed) | ✅ | ❌ | `rollp`/`pick` |
| Math expression engine | ✅ | ❌ | PEMDAS operators |
| Character-by-character scanning | ✅ | ❌ | Parser approach |
| Error recovery | ✅ | ❌ | Invalid blocks as text |

---

## 2. Lorebook / World Info

### 2.1 Entry Structure

| Field | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `key` | ✅ | ❌ | Primary keywords |
| `secondkey` | ✅ | ❌ | Secondary keywords |
| `content` | ✅ | ❌ | Entry text + decorators |
| `insertorder` | ✅ | ❌ | Priority/order |
| `comment` | ✅ | ❌ | Display name |
| `mode` | ✅ | ❌ | multiple/constant/normal/child/folder |
| `alwaysActive` | ✅ | ❌ | Always include |
| `selective` | ✅ | ❌ | Require both keys |
| `useRegex` | ✅ | ❌ | Regex patterns |
| `activationPercent` | ✅ | ❌ | Legacy probability |
| `risu_case_sensitive` | ✅ | ❌ | Case sensitivity |

### 2.2 Decorators (30+)

#### Position Decorators

| Decorator | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@end` | ✅ | ❌ | Position = depth, depth = 0 |
| `@depth` | ✅ | ❌ | Set insertion depth |
| `@reverse_depth` | ✅ | ❌ | Reverse depth (from end) |
| `@role` | ✅ | ❌ | Set message role |
| `@position` | ✅ | ❌ | pt_*, after_desc, etc. |

#### Activation Decorators

| Decorator | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@activate` | ✅ | ❌ | Force activation |
| `@dont_activate` | ✅ | ❌ | Force deactivation |
| `@activate_only_after` | ✅ | ❌ | Min message count |
| `@activate_only_every` | ✅ | ❌ | Modulo activation |
| `@is_greeting` | ✅ | ❌ | Specific greeting only |
| `@probability` | ✅ | ❌ | Random chance (0-100) |

#### Key Decorators

| Decorator | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@additional_keys` | ✅ | ❌ | Add extra keywords |
| `@exclude_keys` | ✅ | ❌ | Exclude if ANY matches |
| `@exclude_keys_all` | ✅ | ❌ | Exclude if ALL match |
| `@match_full_word` | ✅ | ❌ | Full-word matching |
| `@match_partial_word` | ✅ | ❌ | Partial matching |

#### Recursion Decorators

| Decorator | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@recursive` | ✅ | ❌ | Enable recursive scanning |
| `@unrecursive` | ✅ | ❌ | Disable recursive |
| `@no_recursive_search` | ✅ | ❌ | Don't search in activated |

#### Injection Decorators

| Decorator | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@inject_lore` | ✅ | ❌ | Inject into entry (append) |
| `@inject_at` | ✅ | ❌ | Inject at position |
| `@inject_replace` | ✅ | ❌ | Replace operation |
| `@inject_prepend` | ✅ | ❌ | Prepend operation |

#### State Decorators

| Decorator | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@keep_activate_after_match` | ✅ | ❌ | Persist via chat var |
| `@dont_activate_after_match` | ✅ | ❌ | Prevent re-activation |
| `@ignore_on_max_context` | ✅ | ❌ | Priority = -1000 |

#### Other Decorators

| Decorator | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@scan_depth` | ✅ | ❌ | Override scan depth |
| `@priority` | ✅ | ❌ | Custom priority |
| `@disable_ui_prompt` | ✅ | ❌ | Hide UI prompts |
| `@instruct_depth` | ⚠️ | 🚫 | NOT IMPLEMENTED in RisuAI |
| `@reverse_instruct_depth` | ⚠️ | 🚫 | NOT IMPLEMENTED in RisuAI |

### 2.3 Keyword Matching

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Full-word matching | ✅ | ❌ | Split on spaces |
| Partial matching | ✅ | ❌ | Substring match |
| Regex matching | ✅ | ❌ | /pattern/flags |
| Case-insensitive | ✅ | ❌ | Default |
| Selective logic (AND) | ✅ | ❌ | key AND secondkey |

### 2.4 Activation Loop

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Iterative activation | ✅ | ❌ | While loop |
| Recursive scanning | ✅ | ❌ | Add to next iteration |
| Infinite loop prevention | ✅ | ❌ | activatedIndexes set |
| Child entry linking | ✅ | ❌ | Parent must activate |

### 2.5 Token Budget

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Priority sorting | ✅ | ❌ | Descending |
| Budget enforcement | ✅ | ❌ | Cumulative check |
| `@ignore_on_max_context` | ✅ | ❌ | Priority -1000 |

### 2.6 Lore Sources

| Source | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `character.globalLore` | ✅ | ❌ | Character lorebook |
| `chat.localLore` | ✅ | ❌ | Chat-specific |
| Module lorebooks | ✅ | ❌ | From modules |

---

## 3. Prompt Assembly

### 3.1 Template Card Types (6)

| Type | RisuAI | TavernKit | Description |
|------|--------|-----------|-------------|
| `plain` | ✅ | ❌ | Text with role |
| `typed` | ✅ | ❌ | persona/description/lorebook/etc. |
| `chat` | ✅ | ❌ | Chat history slice |
| `authornote` | ✅ | ❌ | Author's note |
| `chatML` | ✅ | ❌ | Raw ChatML format |
| `cache` | ✅ | ❌ | Anthropic cache marker |

### 3.2 Typed Card Subtypes

| Subtype | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| `persona` | ✅ | ❌ | User persona |
| `description` | ✅ | ❌ | Character description |
| `lorebook` | ✅ | ❌ | Activated lore |
| `postEverything` | ✅ | ❌ | Auto-appended |
| `memory` | ✅ | ❌ | Memory system |

### 3.3 Plain Card Type2 Values

| Type2 | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `normal` | ✅ | ❌ | Standard |
| `globalNote` | ✅ | ❌ | Global note |
| `main` | ✅ | ❌ | Main prompt |

### 3.4 Template Features

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| `{{position::name}}` injection | ✅ | ❌ | Dynamic placement |
| `innerFormat` wrapping | ✅ | ❌ | Via `{{slot}}` |
| `postEverything` auto-append | ✅ | ❌ | If missing |
| `utilityBot` bypass | ✅ | ❌ | Skip normal prompt |

### 3.5 ST Preset Import

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| `stChatConvert()` | ✅ | ❌ | ST → RisuAI |
| `main` → plain/main | ✅ | ❌ | |
| `jailbreak` → jailbreak | ✅ | ❌ | |
| `chatHistory` → chat | ✅ | ❌ | |
| `worldInfoBefore` → lorebook | ✅ | ❌ | |
| `charDescription` → description | ✅ | ❌ | |
| `personaDescription` → persona | ✅ | ❌ | |

---

## 4. Regex Scripts

### 4.1 Execution Types (6)

| Type | RisuAI | TavernKit | When |
|------|--------|-----------|------|
| `modify input` | ✅ | ❌ | User submits |
| `modify output` | ✅ | ❌ | AI responds |
| `Modify Request Data` | ✅ | ❌ | Before API |
| `Modify Display` | ✅ | ❌ | Before display |
| `Edit Translation Display` | ✅ | ❌ | Translation |
| `Disabled` | ✅ | ❌ | Never |

### 4.2 Flag System

| Flag | RisuAI | TavernKit | Effect |
|------|--------|-----------|--------|
| `g`/`i`/`m`/`s`/`u` | ✅ | ❌ | Standard regex flags |
| `<order N>` | ✅ | ❌ | Execution priority |
| `<cbs>` | ✅ | ❌ | Parse IN as CBS |
| `<move_top>` | ✅ | ❌ | Output to start |
| `<move_bottom>` | ✅ | ❌ | Output to end |
| `<repeat_back>` | ✅ | ❌ | Repeat previous match |
| `<inject>` | ✅ | ❌ | Inject into history |
| `<no_end_nl>` | ✅ | ❌ | No auto-newline |

### 4.3 Special Directives

| Directive | RisuAI | TavernKit | Effect |
|-----------|--------|-----------|--------|
| `@@emo` | ✅ | ❌ | Emotion trigger |
| `@@inject` | ✅ | ❌ | Store in history |
| `@@move_top` | ✅ | ❌ | Move to start |
| `@@move_bottom` | ✅ | ❌ | Move to end |
| `@@repeat_back` | ✅ | ❌ | Repeat match |

### 4.4 Script Features

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| LRU cache (1000 entries) | ✅ | ❌ | Performance |
| CBS before regex | ✅ | ❌ | Processing order |
| Script ordering | ✅ | ❌ | By `<order>` |

---

## 5. Trigger System

### 5.1 Trigger Types (6)

| Type | RisuAI | TavernKit | When |
|------|--------|-----------|------|
| `start` | ✅ | ❌ | Initialization |
| `manual` | ✅ | ❌ | User-triggered |
| `output` | ✅ | ❌ | After AI response |
| `input` | ✅ | ❌ | User submits |
| `display` | ✅ | ❌ | Before display |
| `request` | ✅ | ❌ | Before API |

### 5.2 Condition Types (3)

| Type | RisuAI | TavernKit | Notes |
|------|--------|-----------|-------|
| `var`/`value` | ✅ | ❌ | Variable condition |
| `exists` | ✅ | ❌ | Text existence |
| `chatindex` | ✅ | ❌ | Chat index condition |

### 5.3 V1 Effects (16)

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `setvar` | ✅ | ❌ | Set variable |
| `cutchat` | ✅ | ❌ | Truncate chat |
| `modifychat` | ✅ | ❌ | Edit message |
| `systemprompt` | ✅ | ❌ | Add system prompt |
| `impersonate` | ✅ | ❌ | Simulate role |
| `command` | ✅ | ❌ | Multi-command |
| `stop` | ✅ | ❌ | Halt execution |
| `runtrigger` | ✅ | ❌ | Chain trigger |
| `showAlert` | ✅ | ❌ | Display alert (lowLevel) |
| `extractRegex` | ✅ | ❌ | Regex extract (lowLevel) |
| `runLLM` | ✅ | ❌ | Call AI (lowLevel) |
| `checkSimilarity` | ✅ | ❌ | Vector similarity |
| `sendAIprompt` | ✅ | ❌ | Send to AI (lowLevel) |
| `runImgGen` | ✅ | ❌ | Image gen (lowLevel) |
| `triggercode` | ✅ | ❌ | Custom code |
| `triggerlua` | ✅ | ❌ | Lua code |

### 5.4 V2 Effects (60+)

#### Control Flow

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2If` | ✅ | ❌ | Conditional |
| `v2Else` | ✅ | ❌ | Else branch |
| `v2EndIndent` | ✅ | ❌ | End block |
| `v2Loop` | ✅ | ❌ | Loop |
| `v2LoopNTimes` | ✅ | ❌ | N iterations |
| `v2BreakLoop` | ✅ | ❌ | Break |

#### Variables

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2SetVar` | ✅ | ❌ | Set variable |
| `v2MakeArrayVar` | ✅ | ❌ | Create array |
| `v2MakeDictVar` | ✅ | ❌ | Create dict |
| `v2DeclareLocalVar` | ✅ | ❌ | Local scope |

#### String Operations (8)

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2ToLowerCase` | ✅ | ❌ | |
| `v2ToUpperCase` | ✅ | ❌ | |
| `v2SplitString` | ✅ | ❌ | |
| `v2JoinArrayVar` | ✅ | ❌ | |
| `v2ReplaceString` | ✅ | ❌ | |
| `v2GetCharAt` | ✅ | ❌ | |
| `v2SetCharAt` | ✅ | ❌ | |
| `v2ConcatString` | ✅ | ❌ | |

#### Array Operations (11)

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2GetArrayVar` | ✅ | ❌ | |
| `v2SetArrayVar` | ✅ | ❌ | |
| `v2PushArrayVar` | ✅ | ❌ | |
| `v2PopArrayVar` | ✅ | ❌ | |
| `v2ShiftArrayVar` | ✅ | ❌ | |
| `v2UnshiftArrayVar` | ✅ | ❌ | |
| `v2SpliceArrayVar` | ✅ | ❌ | |
| `v2SliceArrayVar` | ✅ | ❌ | |
| `v2GetIndexOfValueInArrayVar` | ✅ | ❌ | |
| `v2RemoveIndexFromArrayVar` | ✅ | ❌ | |
| `v2ArrayLength` | ✅ | ❌ | |

#### Dict Operations (8)

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2GetDictVar` | ✅ | ❌ | |
| `v2SetDictVar` | ✅ | ❌ | |
| `v2DeleteDictKey` | ✅ | ❌ | |
| `v2HasDictKey` | ✅ | ❌ | |
| `v2ClearDict` | ✅ | ❌ | |
| `v2GetDictKeys` | ✅ | ❌ | |
| `v2GetDictValues` | ✅ | ❌ | |
| `v2GetDictSize` | ✅ | ❌ | |

#### Chat Operations (7)

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2GetLastMessage` | ✅ | ❌ | |
| `v2GetFirstMessage` | ✅ | ❌ | |
| `v2GetMessageAtIndex` | ✅ | ❌ | |
| `v2GetMessageCount` | ✅ | ❌ | |
| `v2CutChat` | ✅ | ❌ | |
| `v2ModifyChat` | ✅ | ❌ | |
| `v2UpdateChatAt` | ✅ | ❌ | |

#### Lorebook CRUD (9)

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2ModifyLorebook` | ✅ | ❌ | |
| `v2GetLorebook` | ✅ | ❌ | |
| `v2GetLorebookCount` | ✅ | ❌ | |
| `v2GetLorebookEntry` | ✅ | ❌ | |
| `v2SetLorebookActivation` | ✅ | ❌ | |
| `v2GetLorebookIndexViaName` | ✅ | ❌ | |
| `v2CreateLorebook` | ✅ | ❌ | |
| `v2ModifyLorebookByIndex` | ✅ | ❌ | |
| `v2DeleteLorebookByIndex` | ✅ | ❌ | |

#### Character/Persona (4)

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2GetCharacterDesc` | ✅ | ❌ | |
| `v2SetCharacterDesc` | ✅ | ❌ | |
| `v2GetPersonaDesc` | ✅ | ❌ | |
| `v2SetPersonaDesc` | ✅ | ❌ | |

#### System/Request/UI

| Effect | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| `v2SystemPrompt` | ✅ | ❌ | |
| `v2GetRequestState` | ✅ | ❌ | |
| `v2GetDisplayState` | ✅ | ❌ | |
| `v2SetDisplayState` | ✅ | ❌ | |
| `v2UpdateGUI` | ✅ | ❌ | |
| `v2GetAlertInput` | ✅ | ❌ | |
| `v2GetAlertSelect` | ✅ | ❌ | |

### 5.5 V2 Features

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Indent-based control flow | ✅ | ❌ | Block nesting |
| Local variable scoping | ✅ | ❌ | By indent level |
| Extra conditions (∈∋∉∌≒≡) | ✅ | ❌ | Set/contains |
| Recursion limit (10) | ✅ | ❌ | Safety |
| `lowLevelAccess` gating | ✅ | ❌ | Security |

---

## 6. Pipeline

### 6.1 Four Stages

| Stage | RisuAI | TavernKit | Description |
|-------|--------|-----------|-------------|
| 1. Prompt Preparation | ✅ | ❌ | Load lore, build categories |
| 2. Memory Integration | ✅ | ❌ | Hypa/Supa compression |
| 3. Final Formatting | ✅ | ❌ | Apply template, merge |
| 4. API Request | ✅ | ❌ | Send, handle response |

### 6.2 Message Processing Flow

| Step | RisuAI | TavernKit | Notes |
|------|--------|-----------|-------|
| User input | ✅ | ❌ | Entry |
| Lua edit triggers | ✅ | ⏸️ | Optional |
| Plugin V2 hooks | ✅ | ⏸️ | Optional |
| Regex scripts (input) | ✅ | ❌ | |
| CBS parser | ✅ | ❌ | |
| AI request | ✅ | ❌ | |
| AI response | ✅ | ❌ | |
| Triggers (output) | ✅ | ❌ | |
| Regex scripts (output) | ✅ | ❌ | |
| Plugin hooks | ✅ | ⏸️ | Optional |
| Display processing | ✅ | ❌ | |

---

## 7. Memory System

### 7.1 Algorithms

| Algorithm | RisuAI | TavernKit | Notes |
|-----------|--------|-----------|-------|
| HypaMemory V1 | ✅ | ❌ | `db.hanuraiEnable` |
| HypaMemory V2 | ✅ | ❌ | `db.hypav2` |
| HypaMemory V3 | ✅ | ❌ | `db.hypaV3` (recommended) |
| SupaMemory | ✅ | ❌ | Default |

### 7.2 Integration

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Stage 2 hook | ✅ | ❌ | Pipeline integration |
| Compression | ✅ | ❌ | Summarize old messages |
| `memory` prompt type | ✅ | ❌ | Template placement |

---

## 8. Character Cards

### 8.1 Import Formats

| Format | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| CharacterCardV3 (CCv3) | ✅ | ✅ | Via Core |
| CharacterCardV2Risu | ✅ | ✅ | Via Core |
| OldTavernChar | ✅ | ✅ | Via Core |
| CharX (.charx) | ✅ | ⏸️ | Deferred |
| JPEG-wrapped CharX | ✅ | ⏸️ | Deferred |

### 8.2 RisuAI-Specific Fields

| Field | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `bias` | ✅ | ❌ | Token bias overrides |
| `emotionImages` | ✅ | ❌ | Emotion mapping |
| `customscript` | ✅ | ❌ | Regex scripts |
| `triggerscript` | ✅ | ❌ | Triggers |
| `utilityBot` | ✅ | ❌ | Utility mode flag |
| `viewScreen` | ✅ | ❌ | Display mode |
| `sdData` | ✅ | ❌ | SD generation |

---

## 9. Tokenizer

### 9.1 Supported Types (10)

| Type | RisuAI | TavernKit | Backend |
|------|--------|-----------|---------|
| `tik` | ✅ | ✅* | Tiktoken (via Core) |
| `mistral` | ✅ | ⏸️ | Custom |
| `novelai` | ✅ | ⏸️ | SentencePiece |
| `claude` | ✅ | ⏸️ | Claude tokenizer |
| `llama` | ✅ | ⏸️ | SentencePiece |
| `llama3` | ✅ | ⏸️ | JSON tokenizer |
| `novellist` | ✅ | ⏸️ | SentencePiece |
| `gemma` | ✅ | ⏸️ | SentencePiece |
| `cohere` | ✅ | ⏸️ | JSON tokenizer |
| `deepseek` | ✅ | ⏸️ | JSON tokenizer |

\* Core provides tiktoken_ruby; other tokenizers via pluggable interface.

---

## 10. Deferred / Out of Scope

| Feature | RisuAI | TavernKit | Reason |
|---------|--------|-----------|--------|
| Plugin V3 API | ✅ | 🚫 | Sandboxed iframes; not applicable |
| Lua/Python engine | ✅ | ⏸️ | Scripting complexity |
| .risum modules | ✅ | ⏸️ | Module bundling |
| Image generation | ✅ | ⏸️ | Provider-specific |
| Hidden metadata | ✅ | ⏸️ | Watermarking |
| Full tokenizer suite | ✅ | ⏸️ | Beyond Core interface |

---

## Summary by Component

| Component | Total Features | Implemented | Remaining |
|-----------|---------------|-------------|-----------|
| CBS Engine | ~170 | 0 | ~170 |
| Lorebook | ~50 | 0 | ~50 |
| Prompt Assembly | ~25 | 0 | ~25 |
| Regex Scripts | ~25 | 0 | ~25 |
| Triggers | ~90 | 0 | ~90 |
| Pipeline | ~15 | 0 | ~15 |
| Memory | ~5 | 0 | ~5 |
| Character Cards | ~10 | ~5 | ~5 |
| **Total** | **~390** | **~5** | **~385** |

---

## Reference

- RisuAI alignment delta: `docs/rewrite/risuai-alignment-delta.md`
- ST/RisuAI parity: `docs/rewrite/st-risuai-parity.md`
- Roadmap: `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md`
- Core interface design: `docs/rewrite/core-interface-design.md`
