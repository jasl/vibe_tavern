# SillyTavern Compatibility Matrix

Reference: SillyTavern v1.15.0 behavior (staging snapshot `resources/SillyTavern` @ `bba43f332`)
TavernKit layer: `TavernKit::SillyTavern`
Last audited: 2026-02-02

This matrix is meant to be *operational*, not aspirational: it reflects what
TavernKit currently does, plus any intentional divergences.

Status legend:
- ✅ Parity (implemented / covered by tests)
- ⚠️ Partial parity (implemented, but with known deltas)
- ❌ Not supported
- ⏸️ Deferred (planned, not implemented in this rewrite batch)
- 🚫 Intentional divergence (we intentionally do something different)

Scope notes:
- TavernKit focuses on **prompt building** (inputs → prompt plan/messages).
- TavernKit does **not** ship a UI, persistence layer, plugin system, or any
  provider networking. Those belong to downstream apps.

---

## 0. High-level Components

| Component | ST | TavernKit | Notes |
|----------|----|-----------|-------|
| Character cards (CCv2/CCv3) | ✅ | ✅ | Hash-first model layer + exporters |
| PNG metadata | ✅ | ✅ | Read/write `chara` (CCv2) + `ccv3` chunks |
| Macro engines | ✅ | ✅ | Legacy engine + V2 engine (MacroEngine-style) |
| World Info / lorebook | ✅ | ✅ | Keyword + JS-regex keys + budget + timed effects |
| PromptManager / injection | ✅ | ✅ | Ordering, in-chat depth, pinned groups, overrides |
| Group chat strategy | ✅ | ✅ | NATURAL/LIST/MANUAL/POOLED; APPEND merge helpers |
| Trimming / budgeting | ✅ | ✅ | ST budgeting + “preserve latest user” rule |
| Dialects conversion | ✅ | ✅ | `:openai`, `:anthropic`, `:text`, etc (Core) |

---

## 1. Character Cards + ST Extensions

### 1.1 CCv2 / CCv3 core fields

| Feature | CCv2 | CCv3 | TavernKit |
|---------|------|------|-----------|
| spec identifier | ✅ | ✅ | ✅ |
| `data` wrapper | ✅ | ✅ | ✅ |
| `name`/`description`/`personality` | ✅ | ✅ | ✅ |
| `scenario` | ✅ | ✅ | ✅ |
| `first_mes` | ✅ | ✅ | ✅ |
| `mes_example` | ✅ | ✅ | ✅ |
| `alternate_greetings` | ✅ | ✅ | ✅ |
| `system_prompt` | ✅ | ✅ | ✅ |
| `post_history_instructions` | ✅ | ✅ | ✅ |
| `creator_notes` | ✅ | ✅ | ✅ |
| `character_book` | ✅ | ✅ | ✅ |
| `tags` | ✅ | ✅ | ✅ |
| `creator` | ✅ | ✅ | ✅ |
| `character_version` | ✅ | ✅ | ✅ |
| `extensions` (preserved as-is) | ✅ | ✅ | ✅ |
| `group_only_greetings` | ❌ | ✅ | ✅ |
| `assets` | ❌ | ✅ | ✅ |
| `nickname` | ❌ | ✅ | ✅ |
| `creator_notes_multilingual` | ❌ | ✅ | ✅ |
| `source` | ❌ | ✅ | ✅ |
| `creation_date` | ❌ | ✅ | ✅ |
| `modification_date` | ❌ | ✅ | ✅ |

### 1.2 SillyTavern `data.extensions` keys

| Key | ST | TavernKit | Notes |
|-----|----|-----------|-------|
| `talkativeness` | ✅ | ✅ | Used by `SillyTavern::GroupContext` |
| `world` | ✅ | ✅ | `Character#world_name` |
| `extra_worlds` | ✅ | ✅ | Supported (ST may ignore extra names) |
| `depth_prompt` | ✅ | ✅ | Used by lore scan input + `{{charDepthPrompt}}` |
| `fav` | ✅ | 🚫 | UI-only; preserved but not interpreted |

### 1.3 Forward-compat for unknown keys

| Behavior | ST | TavernKit |
|----------|----|-----------|
| Preserve unknown keys under `data.extensions` | ✅ | ✅ |
| Preserve unknown keys at all levels | ✅ | 🚫 |

Rationale: TavernKit intentionally does not preserve unknown, non-`extensions`
keys in exports (to keep the internal model semantic and avoid “opaque blobs”).

---

## 2. File Ingestion (Untrusted External Formats)

TavernKit core objects are **hash-first**. File formats are handled by
`TavernKit::Ingest` and `TavernKit::Archive::*`.

| Format | ST | TavernKit | Notes |
|--------|----|-----------|-------|
| PNG/APNG CC wrapper | ✅ | ✅ | Returns Character + original image path |
| CHARX (`.charx`, zip) | ✅ | ✅ | Extracts `card.json` + exposes lazy assets |
| BYAF (`.byaf`, zip) | ✅ | ✅ | Extracts one character + exposes scenarios hash + lazy assets |

---

## 3. Macro System

### 3.1 Engines

| Engine | ST | TavernKit | Notes |
|--------|----|-----------|-------|
| Legacy substitution (`substituteParamsLegacy`) | ✅ | ✅ | `SillyTavern::Macro::V1Engine` |
| MacroEngine / “Macros 2.0” | ✅ | ✅ | `SillyTavern::Macro::V2Engine` |

### 3.2 V2 engine semantics (MacroEngine-like)

| Behavior | ST | TavernKit | Notes |
|----------|----|-----------|-------|
| Nested macros in args | ✅ | ✅ | Depth-first, left-to-right |
| Unknown macros preserved | ✅ | ✅ | Preserved for later expansion |
| `{{if}}...{{else}}...{{/if}}` | ✅ | ✅ | Block support + flags |
| Deterministic `{{pick}}` (offset-based) | ✅ | ⚠️ | Deterministic, but seeding differs; see delta doc |
| Pre/post-processing pipeline | ✅ | ✅ | Includes `<USER>` etc normalization |

### 3.3 Macro packs

| Pack | ST | TavernKit | Notes |
|------|----|-----------|-------|
| Core (`{{char}}`, `{{user}}`, `{{original}}`, …) | ✅ | ✅ | |
| Chat/history macros | ✅ | ✅ | `{{lastMessage}}`, `{{lastUserMessage}}`, … |
| Time/date macros | ✅ | ✅ | `{{date}}`, `{{time}}`, `{{datetimeformat}}`, … |
| Variables (`var` + `globalvar`) | ✅ | ✅ | Stored in `ctx.variables_store` |
| Instruct macros (`{{instruct...}}`) | ✅ | ✅ | Based on `ctx.preset.instruct` |
| State/env macros | ✅ | ✅ | Requires app-supplied state for strict parity |

### 3.4 Known macro deltas

See:
- `docs/compatibility/sillytavern-deltas.md`

---

## 4. World Info / Lorebook

| Feature | ST | TavernKit | Notes |
|---------|----|-----------|-------|
| Keyword matching + selective logic | ✅ | ✅ | |
| Secondary keys | ✅ | ✅ | |
| Regex keys (JS) | ✅ | ⚠️ | Uses JS→Ruby conversion; some JS features may be unsupported |
| whole-word + case-sensitive options | ✅ | ✅ | |
| Constant entries | ✅ | ✅ | |
| Positions (8 types) | ✅ | ✅ | incl. `at_depth` + `outlet` |
| Token budget | ✅ | ✅ | Budget enforcement + ordering |
| Recursive scanning + scan_depth semantics | ✅ | ✅ | |
| Timed effects (sticky/cooldown/delay) | ✅ | ✅ | |
| Probability + `useProbability` | ✅ | ✅ | |
| Trigger filters (`triggers[]`) | ✅ | ✅ | Based on generation type |
| Forced activations | ✅ | ✅ | Via `ctx.forced_world_info_activations` |
| Decorators (`@@activate`, `@@dont_activate`) | ✅ | ✅ | |
| Automation callbacks/events | ✅ | ❌ | App layer concern; hook surface is minimal |

---

## 5. Prompt Manager / Injection

| Feature | ST | TavernKit | Notes |
|---------|----|-----------|-------|
| `prompt_entries` ordering + enable rules | ✅ | ✅ | Entry normalization supported |
| Overrides: prefer/forbid/`{{original}}` splicing | ✅ | ✅ | |
| Pinned groups (main/persona/description/…) | ✅ | ✅ | |
| In-chat injection depth semantics | ✅ | ✅ | Reverse-depth + role ordering covered by tests |
| Same depth/order/role merging | ✅ | ✅ | |
| Persona description positions (5) | ✅ | ✅ | AFTER_CHAR is treated as deprecated |
| Author’s Note interval + positions | ✅ | ✅ | |
| Continue / impersonate prompts | ✅ | ✅ | Includes assistant prefill behavior |
| continue+continue_prefill displacement | ✅ | ✅ | Matches ST openai.js behavior |
| Group nudge prompt | ✅ | ✅ | |

---

## 6. Group Chat

| Feature | ST | TavernKit | Notes |
|---------|----|-----------|-------|
| Activation strategies (NATURAL/LIST/MANUAL/POOLED) | ✅ | ✅ | `SillyTavern::GroupContext.decide` |
| Special gen types override strategy (quiet/swipe/continue/impersonate) | ✅ | ✅ | |
| APPEND / APPEND_DISABLED card merging | ✅ | ✅ | `SillyTavern::GroupContext.merge_cards` |
| Scheduling sync (app vs pipeline) | ✅ | ✅ | `GroupContext.decision_matches?` helper |

---

## 7. Trimming / Budgeting

| Feature | ST | TavernKit | Notes |
|---------|----|-----------|-------|
| ST budget rule (`max_prompt = ctx_window - reserved`) | ✅ | ✅ | See `docs/contracts/prompt-orchestration.md` |
| Strategy `:group_order` (examples → lore → history) | ✅ | ✅ | Examples evict as dialogue bundles |
| Preserve latest user message | ✅ | ✅ | |
| Trim report + observability | ✅ | ✅ | `ctx.trim_report` |
| Over-budget after evictions → error | ✅ | ✅ | `TavernKit::MaxTokensExceededError` |

---

## 8. Dialects / Tool Use (Core)

TavernKit provides provider payload conversion via `TavernKit::Dialects`.

| Dialect | ST | TavernKit |
|---------|----|-----------|
| OpenAI ChatCompletions | ✅ | ✅ |
| Anthropic messages | ✅ | ✅ |
| Text completion | ✅ | ✅ |
| (AI21/Cohere/Google/Mistral/xAI) | ✅ | ✅ | Supported at Core-level conversion |

Tool/function calling:
- Core supports standardized message metadata (`:tool_calls`, `:tool_call_id`)
  and dialect passthrough.
- ST-specific “tool calling prompt-building” behaviors are **not** implemented
  as a first-class feature (app layer).

---

## 9. Deferred / Out of Scope

| Feature | ST | TavernKit | Reason |
|---------|----|-----------|--------|
| ST UI (MacroBrowser, lore UI, etc.) | ✅ | 🚫 | Gem has no UI |
| Chat JSONL persistence + metadata headers | ✅ | 🚫 | App layer |
| STscript full parser | ✅ | ⏸️ | High complexity / low value for this batch |
| Data Bank / RAG | ✅ | ⏸️ | App layer (TavernKit exposes hooks/interfaces) |

---

## References

- Prompt orchestration contracts: `docs/contracts/prompt-orchestration.md`
- ST deltas: `docs/compatibility/sillytavern-deltas.md`
