# SillyTavern / RisuAI Parity Checklist (2026-01-28)

## Status
- **Primary reference:** SillyTavern (confirmed).
- **RisuAI source:** `resources/Risuai` (scanned for parity notes).
- **Implementation priority:** SillyTavern first; RisuAI notes/tests are backlog until ST parity is stable.

## Sources Scanned (SillyTavern)
- Character card PNG handling: `resources/SillyTavern/src/character-card-parser.js`
- BYAF import: `resources/SillyTavern/src/byaf.js`
- Macro engine (new): `resources/SillyTavern/public/scripts/macros/engine/*`
- Macro definitions (new): `resources/SillyTavern/public/scripts/macros/definitions/*`
- Legacy macro bridge: `resources/SillyTavern/public/scripts/macros.js`
- Prompt manager + prompt assembly: `resources/SillyTavern/public/scripts/PromptManager.js`, `resources/SillyTavern/public/scripts/openai.js`
- World Info / Lorebook: `resources/SillyTavern/public/scripts/world-info.js`
- Instruct mode: `resources/SillyTavern/public/scripts/instruct-mode.js`
- Author's Note / floating prompt: `resources/SillyTavern/public/scripts/authors-note.js`

## Sources Scanned (RisuAI)
- Character card PNG + CCv3: `resources/Risuai/src/ts/pngChunk.ts`, `resources/Risuai/src/ts/characterCards.ts`
- CBS macros + parser: `resources/Risuai/src/ts/cbs.ts`, `resources/Risuai/src/ts/parser.svelte.ts`
- CBS docs: `resources/Risuai/src/etc/docs/cbs_intro.cbs`, `resources/Risuai/src/etc/docs/cbs_docs.cbs`
- Lorebook processing: `resources/Risuai/src/ts/process/lorebook.svelte.ts`
- Prompt assembly + templates: `resources/Risuai/src/ts/process/index.svelte.ts`, `resources/Risuai/src/ts/process/prompt.ts`, `resources/Risuai/src/ts/process/templates/templates.ts`
- Data model fields: `resources/Risuai/src/ts/storage/database.svelte.ts`

---

## Parity Checklist (SillyTavern → TavernKit)

### 1) Character Cards / Import & Export
- **PNG metadata**
  - Write: remove existing `tEXt` with `chara`/`ccv3`, write `chara` (v2) and attempt `ccv3` (v3) before `IEND`.
  - Read: prefer `ccv3` if present, else `chara`.
- **BYAF import behavior**
  - Replace `#{user}:`/`#{character}:` and `{user}`/`{character}` with `{{user}}`/`{{char}}`.
  - Example messages formatted as `<START>\n...` with macro replacement.
  - Alternate greetings skip first scenario; de-dup and ignore identical first message.
- **Card fields & extensions**
  - Preserve `extensions` with unknown keys (e.g., `talkativeness`, `world`, `extra_worlds`).
  - `group_only_greetings` (v3) and assets handling; v3 preferred but v2 supported.

### 2) Macro System (SillyTavern compatibility module)
- **Dual engine**
  - Legacy regex-based `MacrosParser` still supported.
  - New parser engine exists (gated by `experimental_macro_engine`).
- **Macro syntax + lexer rules**
  - `{{macro}}`, `{{macro::arg}}` (unnamed args), named args via `=`.
  - Scoped macros `{{macro}}...{{/macro}}` with `{{else}}` support.
  - Macro flags: `! ? ~ / #` (see lexer for semantics; `#` preserves whitespace).
  - Variable shorthand: `.var` (local) and `$var` (global) with operators (`=`, `+=`, `-=`, `++`, `--`, `??`, `||`, comparisons).
- **Flag support**
  - `/` (closing block) and `#` (preserve whitespace) are implemented.
  - `! ? ~` are parsed but not implemented (behavior unchanged).
  - `>` (filter/pipe) is parsed; output filters are not implemented yet.
- **Pre/post processing**
  - Legacy markers `<USER>/<BOT>/<CHAR>/<GROUP>/<CHARIFNOTGROUP>` rewritten to macro form.
  - Legacy time syntax `{{time_UTC-10}}` rewritten to `{{time::UTC-10}}`.
  - Post-process unescapes `\{` and `\}`, and strips `{{trim}}` with surrounding newlines.
- **Scoped content trimming**
  - Scoped macro content is trimmed and dedented by default.
  - `#` flag preserves whitespace (legacy handlebars style).
- **Core macro set (new engine)**
  - Utility: `space`, `newline`, `noop`, `trim`, `if/else`, `input`, `maxPrompt`, `reverse`, `//` (comment), `roll`, `random`, `pick`, `banned`, `outlet`.
  - Time: `time`, `date`, `weekday`, `isotime`, `isodate`, `datetimeformat`, `idleDuration`, `timeDiff`.
  - State: `lastGenerationType`, `hasExtension`.
  - Env: `user`, `char`, `group`, `groupNotMuted`, `notChar`, `charPrompt`, `charInstruction`, `charDescription`, `charPersonality`, `charScenario`, `persona`, `mesExamplesRaw`, `mesExamples`, `charDepthPrompt`, `charCreatorNotes`, `charVersion` (aliases `version`, `char_version`), `model`, `original`, `isMobile`.
  - Chat: `lastMessage`, `lastMessageId`, `lastUserMessage`, `lastCharMessage`, `firstIncludedMessageId`, `firstDisplayedMessageId`, `lastSwipeId`, `currentSwipeId`.
  - Variables: `setvar/addvar/incvar/decvar/getvar/hasvar/deletevar` and global variants.
  - Instruct: `systemPrompt` (and related instruct-mode macros).
- **Behavioral notes**
  - `mesExamples` formatting changes under instruct mode.
  - `if` macro resolves macro/variable shorthands in condition; supports scoped `{{else}}`.
  - Unknown macros return raw `{{...}}` (nested macros inside are already resolved).

### 3) Variables & State
- Local and global variable stores exist and are manipulated via macros.
- `addvar`/`addglobalvar` are additive (string append or numeric add).
- Variable existence macros return string `'true'/'false'` (not booleans).

### 4) Prompt Manager + Prompt Assembly (OpenAI path)
- Prompt manager has **default prompt set**: main, nsfw, jailbreak, enhanceDefinitions, new chat, new group chat, example chat, continue nudge, group nudge, impersonation.
- Prompt entries have:
  - role (`system/user/assistant`),
  - injection position (`absolute` vs relative),
  - injection depth + order,
  - per-character enable/disable and prompt order.
- System prompts are merged with prompt-manager prompts; overrides allow role/depth/order changes.
- Relative prompts can be converted to in-chat injections at computed positions.
- Group chats: `group_nudge_prompt` is inserted unless skipped by generation type.
- Continue generation uses `continue_nudge_prompt` with last message content.
- Example chats (`mes_example`) injected via `new_example_chat_prompt`.
- Default prompt order (chat completion): `main`, `worldInfoBefore`, `personaDescription`, `charDescription`, `charPersonality`, `scenario`, `enhanceDefinitions`, `nsfw`, `worldInfoAfter`, `dialogueExamples`, `chatHistory`, `jailbreak`.

### 5) World Info / Lorebook
- Global settings to mirror:
  - `depth`, `budget_percent`, `budget_cap_tokens`, `include_names`, `match_whole_words`, `case_sensitive`, `recursive`, `max_recursion_steps`, `use_group_scoring`, `min_activations`, `min_activations_depth_max`, `insertion_strategy` (evenly/character_first/global_first).
- Lorebook sources & ordering:
  - Chat lorebook → Persona lorebook → Character lorebook → Global lorebooks (see `world-info.js` logs + ordering).
- Entry fields to preserve:
  - primary/secondary keys, selective logic (AND/NOT variants), decorators, insertion order, enabled flag, world name.
  - behavior flags: `constant`, `disable`, `useProbability/probability`, `ignoreBudget`, `preventRecursion`, `excludeRecursion`, `delayUntilRecursion`.
  - timed effects: `sticky`, `cooldown`, `delay` (tracked with indices).
  - filters: `characterFilter` (names/tags) and `triggers` (generation type).
- Timed effects:
  - Sticky/cooldown/delay tracked with start/end indices; protected effects survive non-advancing chat turns.
- Scan data includes persona/character description, personality, depth prompt, scenario, creator notes, and trigger type.
- Decorators:
  - Parsed from leading `@@...` lines; `@@@` is ignored unless fallback parsing kicks in.
  - Known decorators in code: `@@activate`, `@@dont_activate` (others are stored as entry fields).
- Matching logic:
  - Primary + secondary keys with `AND_ALL`, `AND_ANY`, `NOT_ALL`, `NOT_ANY` logic.
  - Case-sensitive and whole-word matching per entry or global defaults.
  - Probability rolls skipped if sticky; failed probability tracked per entry.
- Budgeting:
  - Budget = `round(maxContext * budget_percent / 100)` with optional cap.
  - `ignore_budget` entries can pass after overflow; otherwise scanning stops.
- Recursion:
  - Recursive scans use newly activated entry text; optional delay levels.
  - `exclude_recursion` entries are skipped during recursion phase.

### 6) Author’s Note / Floating Prompt
- Module id is `2_floating_prompt` (sorting intentionally lower than memory).
- Settings to mirror:
  - prompt content, interval, depth, role, position, allow WI scan.
  - character-specific note + default note; position options.

### 7) Instruct Mode
- Presets and settings for sequences:
  - input/output/system sequences + suffixes, story string prefix/suffix, stop sequences.
  - names behavior: `none/force/always`.
  - macro insertion toggle for instruct sequences.
  - optional `system_same_as_user` and `skip_examples`.

### 8) Message / Example Parsing
- `mes_example` uses `<START>` markers; parsed into message blocks.
- Examples are inserted with `new_example_chat_prompt` and can be instruct-formatted.

---

## RisuAI Parity Notes (for alignment)

### 1) Character Cards / Import & Export
- **PNG metadata**
  - Writer strips existing `tEXt` chunks for `chara` and `ccv3`, then writes new data (CCv2 base64 in `chara`, CCv3 base64 in `ccv3`).
  - Import reads both; prefers `ccv3` when present, falls back to `chara`/legacy.
  - Additional embedded assets use `tEXt` keys `chara-ext-asset_...`.
- **Character card fields**
  - Uses `character_book` with `entries`, `scan_depth`, `token_budget`, `recursive_scanning`, `extensions`.
  - Exports/ingests `extensions.risuai` and `extensions.depth_prompt`; preserves unknown extension keys.

### 2) CBS Macro System (RisuAI)
- **Syntax**
  - Macros are `{{...}}`; args can be `:` or `::` separated.
  - Math expression form: `{{? <expr>}}` (supports `+ - * / ^ % < > <= >= || && == != !`).
  - Comments: `{{// ...}}` (non-displayed), `{{comment::...}}` (displayed).
- **Escapes & display tokens**
  - `{{bo}}`/`{{bc}}` render literal `{{` / `}}`; `{{decbo}}`/`{{decbc}}` render `{` / `}`.
  - `{{br}}` renders a newline; `{{cbr}}` renders the literal `\n`.
  - `{{#escape}}...{{/}}` escapes braces/parenthesis (trimmed); `{{#escape::keep}}` preserves whitespace.
  - `{{#pure}}` trims and prevents parsing; `{{#puredisplay}}` trims and escapes `{{`/`}}` in output.
  - `{{#code}}` (normalize) unescapes `\n \t \r \uXXXX` etc; used for literal formatting.
- **Block syntax**
  - `{{#if ...}}...{{/}}` (true only for `1` or `true`), `#if_pure` keeps whitespace.
  - `{{#when::...}}...{{:else}}...{{/}}` supports operators (`is/isnot`, `> >= < <=`, `and/or/not`, `var`, `toggle`, `vis/tis`), plus `keep` and `legacy` modes.
  - `{{#each ... as slot}}...{{/}}` loops arrays; `{{slot::name}}` expansion.
  - `{{#func name args...}}...{{/}}` + `{{call::name::arg1::arg2}}` for reusable CBS blocks.
  - `{{#pure}}`, `{{#puredisplay}}`, `{{#code}}` (normalize escapes), `{{#escape}}` for literal output.
- **Variables & state**
  - Chat vars: `getvar/setvar/addvar/setdefaultvar`; globals: `getglobalvar`.
  - Temp vars: `tempvar/settempvar`; `return` short-circuits CBS parsing.
- **Macro surface**
  - Large built-in catalog (character/user fields, chat history, time/date, RNG, arrays/dicts, assets, modules, etc.).
  - Module-aware macros (e.g., `module_enabled`, `module_assetlist`) and lorebook access.

### 3) Variables / Defaults / Toggles
- Chat variables live under `chat.scriptstate['$key']`; missing values fall back to:
  - `character.defaultVariables` + `db.templateDefaultVariables` (`key=value` per line, **no trimming**).
  - Otherwise `'null'`.
- Global variables are `db.globalChatVariables`; prompt toggles use keys like `toggle_<key>`.
- `#when::toggle::X` checks `globalChatVariables['toggle_X']` for `'1'`/`'true'`.

### 4) Prompt Assembly / Templates
- **Template-driven prompt**: `promptTemplate` is a list of cards (types: `plain`, `chat`, `persona`, `description`, `lorebook`, `authornote`, `jailbreak`, `cot`, `memory`, `cache`, `postEverything`, `chatML`).
  - `innerFormat` can wrap content via `{{slot}}`.
  - Supports `{{position::...}}` slots for lorebook position injection (e.g., `pt_...`, `before_desc`, `after_desc`, `personality`, `scenario`).
  - `postEverything` is appended if missing; `promptSettings` can add `postEndInnerFormat`, force chat-as-system, etc.
  - `utilityBot` bypasses normal prompt unless `promptSettings.utilOverride` is enabled.
- **Non-template path**: builds prompt from `mainPrompt` (ChatML-like via `@@role` blocks), optional `jailbreak`, `globalNote` (replaceable by `replaceGlobalNote`), plus `authorNote` (chat note or default) and `chainOfThought` (post-everything) unless custom.
- **System prompt override**: `character.systemPrompt` can replace `db.mainPrompt` via `{{original}}`.
- **Prompt preprocess**: `db.promptPreprocess` gates appending `db.additionalPrompt` to main prompt.
- **Examples**: inserts example messages and a `[Start a new chat]` marker in most modes.
- **ST prompt import**: RisuAI can convert ST prompt JSON into its template cards (`stChatConvert`), implying compatibility pressure for prompt ordering.

### 5) Lorebook / World Info
- **Sources & ordering**
  - Combines character `globalLore`, chat `localLore`, and module lorebooks.
  - Uses per-character `loreSettings` (tokenBudget, scanDepth, recursiveScanning, fullWordMatching) falling back to DB defaults.
- **Entry fields**
  - `key`, `secondkey`, `selective`, `alwaysActive`, `insertorder` (priority), `useRegex`, `activationPercent`, `mode`, `folder`, `id`.
  - `mode` supports `normal`, `constant`, `multiple`, `child`, `folder`; folders encoded as `\uf000folder:<uuid>` key.
- **Matching rules**
  - Case-folds and strips CBS comments (`{{//}}`, `{{comment:}}`) before matching.
  - Full-word vs partial-word matching is configurable (global or per-entry via decorators).
  - `selective` requires `secondkey` matches in addition to primary keys; `exclude_keys` and `exclude_keys_all` supported via decorators.
  - Regex matching supported via `/regex/flags` strings when `useRegex` is true.
- **Decorators (inline)**
  - `@depth`, `@reverse_depth`, `@scan_depth`, `@role`, `@position`.
  - Activation gates: `@activate_only_after`, `@activate_only_every`, `@is_greeting`, `@probability`, `@activate`, `@dont_activate`.
  - Key controls: `@additional_keys`, `@exclude_keys`, `@exclude_keys_all`, `@match_full_word`, `@match_partial_word`.
  - Recursion: `@recursive`, `@unrecursive`, `@no_recursive_search`, plus persistent toggles `@keep_activate_after_match`, `@dont_activate_after_match`.
  - Injection: `@inject_lore` (inject into other lore entries), `@inject_at`, `@inject_prepend`, `@inject_replace`.
  - UI suppression: `@disable_ui_prompt` supports `post_history_instructions` and `system_prompt`.
- **Budgets**
  - Entries sorted by `priority` (default: `insertorder`), then filtered by token budget.
  - After filtering, entries are re-sorted by `insertorder` and injected (reverse order output).

### 6) Regex Scripts (customscript)
- **Sources**: `db.presetRegex` + `character.customscript` + module regex scripts.
- **Modes**: `editinput`, `editoutput`, `editprocess`, `editdisplay`.
- **Flags/actions**
  - `flag` can include `<...>` meta: `order N` plus actions (`cbs`, `inject`, `repeat_back`, `move_top`, `move_bottom`, `no_end_nl`).
  - `ableFlag` enables custom regex flags (sanitized to `dgimsuvy`).
  - `input` can be CBS-parsed when `cbs` action is present.
- **Output directives**
  - `@@emo <name>` pushes emotion if matched.
  - `@@inject` removes matched text from current message (only when chatID known).
  - `@@move_top` / `@@move_bottom` move matched output to top/bottom.
  - `@@repeat_back <mode>` pulls previous same-role match (`start/end/start_nl/end_nl`).
- **Processing**
  - CBS runs **before** regex scripts.
  - Scripts are ordered by `order` desc when any order provided.
  - Output ending with `>` auto-appends newline unless `no_end_nl`.
  - Result is cached per scripts+data hash (up to 1000 entries).

### 7) Triggers (v1 + v2)
- **Trigger types**: `start`, `manual`, `output`, `input`, `display`, `request`.
  - `manual` matches by trigger `comment` name.
- **Conditions**:
  - `var/value/chatindex` comparisons (`= != > < >= <= null true`).
  - `exists` search in recent chat (`strict` word, `loose` substring, `regex`).
- **V1 effects (subset)**
  - `setvar`, `systemprompt` (start/historyend/promptend), `impersonate`, `command`,
    `cutchat`, `modifychat`, `runtrigger`, `stop`, `extractRegex`, `runLLM`, `runImgGen`,
    `checkSimilarity`, `showAlert`.
  - Many are gated by `lowLevelAccess` (alerts, LLM, regex extract, img gen, send AI prompt).
- **V2 effects (scripted)**
  - Structured control flow: `v2If/v2Else/v2EndIndent`, `v2Loop/v2LoopNTimes`, `v2BreakLoop`.
  - Local vars (`v2DeclareLocalVar`) scoped by indent; falls back to chat vars when absent.
  - Extra conditions: `∈ ∋ ∉ ∌ ≒ ≡` (set/contains/approx/equiv).
  - Rich helpers: get/set messages, prompt state, lorebook CRUD, array/dict ops, string ops,
    tokenize, regex extract, etc.
- **Safety**
  - Recursion limited to 10 unless `lowLevelAccess`.
  - `display` and `request` modes restrict allowed effect types.

### 8) Lua / Script Engine (triggerlua)
- Lua (wasmoon) and optional Python (pyodide) engines, with per-mode API dispatch:
  - `onInput`, `onOutput`, `onStart`, `onButtonClick`, `callListenMain` for edit hooks.
- Access control via generated access keys:
  - `ScriptingSafeIds` allows safe ops; `ScriptingLowLevelIds` gates risky APIs.
- Exposed APIs include chat mutation (cut/insert/remove), var get/set, alert dialogs,
  prompt/token helpers, lorebook access, image generation, and LLM requests.
- `runLuaEditTrigger` hooks `editInput/editOutput/editDisplay/editRequest` pipelines.

### 9) Modules (.risum)
- Module bundle includes lorebook, regex scripts, triggers, assets, and toggles.
- Import/export uses rpack + asset payloads; modules can inject toggle definitions.

## Next Actions

Detailed implementation plans have been refined into the following documents:

- **Roadmap (wave plan + Core interface design):**
  `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md`
- **ST alignment delta (30 action items):**
  `docs/rewrite/st-alignment-delta-v1.15.0.md`
- **RisuAI alignment delta (39 action items):**
  `docs/rewrite/risuai-alignment-delta.md`

High-level summary of remaining work:
- Wave 2: Core interfaces (revised for dual-platform support) + ST config
- Wave 3: Lore engine + Macro engine (ST implementations)
- Wave 4: Middleware chain + Dialects + full `SillyTavern.build()` end-to-end
- Wave 5: RisuAI layer + parity verification
