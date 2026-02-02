# RisuAI Compatibility Matrix

Reference: RisuAI source snapshot `resources/Risuai` @ `b8076cae`
TavernKit layer: `TavernKit::RisuAI`
Last audited: 2026-02-02

This matrix is meant to describe what TavernKit currently implements for RisuAI
parity, and what is intentionally left to downstream apps.

Status legend:
- ✅ Parity (implemented / covered by tests)
- ⚠️ Partial parity (implemented, but with known deltas)
- ❌ Not supported
- ⏸️ Deferred (planned, not implemented in this rewrite batch)
- 🚫 Intentional divergence (we intentionally do something different)

Scope notes (important):
- Scope for RisuAI is **prompt building** (CBS/Lore/Templates/RegexScripts/Triggers),
  with app-state coming from `ctx.runtime` (metadata, toggles, etc).
- UI rendering, storage/DB persistence, and network I/O are **application-owned**.

---

## 0. High-level Components

| Component | RisuAI | TavernKit | Notes |
|----------|--------|-----------|-------|
| Runtime contract (app-state sync) | ✅ | ✅ | `TavernKit::RisuAI::Runtime` + `Prompt::Context#runtime` |
| CBS engine + macro registry | ✅ | ✅ | Prompt-building-focused; unknown macros preserved |
| Lorebook engine (decorators + scanning) | ✅ | ✅ | Decorator-driven behavior, JS regex supported |
| Template cards (promptTemplate) | ✅ | ✅ | Includes `stChatConvert` |
| Regex scripts | ✅ | ✅ | Cached compiled regex + cached outputs |
| Triggers | ✅ | ✅ | Prompt-building-safe effects; UI/DB effects deferred |
| Memory system | ✅ | ✅* | Interface + middleware hooks; algorithms are app-owned |
| Tokenizer suite | ✅ | ⏸️ | Interface-first; full parity deferred |

\* Memory: TavernKit provides the integration surface and data contracts, not a
specific embedding/summarization implementation.

---

## 1. Runtime Contract (App ↔ Pipeline Sync)

RisuAI parity relies on app-provided state. TavernKit standardizes that state as
an immutable runtime object attached to the pipeline context (`ctx.runtime`).

Canonical input form: **snake_case symbol keys** (runtime normalizes once).

| Key | Type | Required | Used for |
|-----|------|----------|----------|
| `chat_index` | Integer | optional | chat position (`{{chatindex}}`, role logic, etc) |
| `message_index` | Integer | optional | deterministic RNG seed (`pick`/`rollp`) |
| `rng_word` | String | optional | deterministic RNG seed word |
| `cbs_conditions` | Hash | optional | matcherArg flags (role/isfirstmsg parity) |
| `toggles` | Hash | optional | `toggle_*` conditions (`#when::toggle` etc) |
| `metadata` | Hash | optional | `{{metadata}}` / app-state macros |
| `modules` | Array | optional | `{{moduleenabled}}` |
| `assets` | Hash/Array | optional | media/UI macro support (app interprets) |

Defaults in tolerant mode (TavernKit-only):
- `chat_index: -1`
- `message_index: (history size or 0)`
- `rng_word: (character name or "0")`
- `cbs_conditions: {}`

See:
- Runtime contract: `docs/core-interface-design.md` (Runtime section)

---

## 2. CBS Macro Engine

Implementation: `TavernKit::RisuAI::CBS::Engine` + `TavernKit::RisuAI::CBS::Macros`.

### 2.1 Syntax + core semantics

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| `{{...}}` delimiter | ✅ | ✅ | |
| `::` argument separator | ✅ | ✅ | Also supports legacy `:` splitting when present |
| Nested macros | ✅ | ✅ | Nested tags inside `{{...}}` expand first |
| `{{#block}}...{{/block}}` syntax | ✅ | ✅ | |
| `{{/}}` shorthand closing | ✅ | ✅ | Any `{{/...}}` closes blocks (tolerant) |
| `{{// comment}}` | ✅ | ✅ | `//` tags render as empty |
| `{{? expr}}` math shorthand | ✅ | ✅ | RPN calculator with var substitution |
| `§`-delimited arrays | ✅ | ✅ | For `#each` / array parsing fallback |
| Unknown macros preserved | ✅ | ✅ | Preserved for later stages |

### 2.2 Block types

| Block | RisuAI | TavernKit | Notes |
|-------|--------|-----------|-------|
| `#when` / `#when::...` | ✅ | ✅ | Operators + modifiers implemented |
| `#if` / `#if_pure` | ✅ | ✅ | Legacy modes supported |
| `#each` | ✅ | ✅ | Iteration + slot substitution |
| `#escape` | ✅ | ✅ | Uses PUA escape rules |
| `#pure` / `#puredisplay` | ✅ | ✅ | |
| `#func` + `call::` | ✅ | ✅ | Per-render function table + call-stack limit |
| `#code` | ✅ | ✅ | Escape-sequence normalization |
| `:else` | ✅ | ✅ | Single-line + multi-line handling |

### 2.3 Macro coverage policy

TavernKit implements the **prompt-building subset** of CBS macros, plus some
“pure text” display helpers (they expand to markup strings, but TavernKit does
not render UI).

Concrete mapping lives in:
- `lib/tavern_kit/risu_ai/cbs/macros.rb`

Known parity caveat:
- Anything that depends on real UI state, storage, or network I/O must be
  provided by the app via runtime metadata/adapters (by design).

---

## 3. Lorebook / World Info

Implementation: `TavernKit::RisuAI::Lore::Engine`.

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Decorator parsing → entry extensions | ✅ | ✅ | `@position/@depth/@role/@inject/...` etc |
| Keyword matching | ✅ | ✅ | |
| Regex matching | ✅ | ⚠️ | JS regex supported (best-effort conversion) |
| Full-word matching | ✅ | ✅ | |
| Multi-pass activation loop | ✅ | ✅ | recursion + state decorators |
| Token budget | ✅ | ✅ | priority-based selection |
| Inject prompts (`@inject`) | ✅ | ✅ | injection map returned to template assembly |
| `pt_*` named positions | ✅ | ✅ | maps into `{{position::name}}` slots |

---

## 4. Template Cards (promptTemplate)

Implementation: `TavernKit::RisuAI::TemplateCards`.

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Card types (`plain/persona/description/lorebook/...`) | ✅ | ✅ | Unknown cards ignored (tolerant) |
| `{{position::x}}` placeholders | ✅ | ✅ | fed by lore `pt_*` positions |
| Lore injection by location | ✅ | ✅ | `@inject` map applied per card |
| `stChatConvert` | ✅ | ✅ | converts STCHAT preset → promptTemplate |
| Cache markers | ✅ | ✅ | emitted as zero-length blocks w/ metadata |

---

## 5. Regex Scripts

Implementation: `TavernKit::RisuAI::RegexScripts` + middleware.

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| 6 execution types | ✅ | ✅ | input/output/request/display/translation/disabled |
| Flag system (`<order>`, `<cbs>`, `<inject>`, …) | ✅ | ✅ | |
| `@@` directives | ✅ | ✅ | emo/inject/move/repeat flags |
| Regex compilation caching | ✅ | ✅ | bounded LRU cache |
| Output caching | ✅ | ✅ | bounded LRU cache |

---

## 6. Trigger System

Implementation: `TavernKit::RisuAI::Triggers` + middleware.

| Feature | RisuAI | TavernKit | Notes |
|---------|--------|-----------|-------|
| Trigger runner (v1 + v2) | ✅ | ✅ | recursion limits + gating |
| Prompt-building-safe effects | ✅ | ✅ | control flow + vars + string/array/dict + chat ops + tokenize/replace |
| UI/DB/network effects | ✅ | ⏸️ | Deferred; must be app-provided via adapters |

Rationale: TavernKit is a prompt-building library. Effects that mutate storage,
touch DB, show UI, or do network I/O are intentionally not implemented here.

---

## 7. Pipeline

Implementation: `TavernKit::RisuAI::Pipeline`.

| Stage | RisuAI | TavernKit |
|-------|--------|-----------|
| Prepare/runtime | ✅ | ✅ |
| CBS expansion | ✅ | ✅ |
| Lore scan | ✅ | ✅ |
| Template assembly | ✅ | ✅ |
| Regex scripts | ✅ | ✅ |
| Triggers | ✅ | ✅ |
| Plan assembly | ✅ | ✅ |

---

## 8. Character Cards + Ingest

| Format | RisuAI | TavernKit | Notes |
|--------|--------|-----------|-------|
| CCv2/CCv3 JSON (hash) | ✅ | ✅ | core model layer is hash-first |
| PNG wrappers | ✅ | ✅ | via `TavernKit::Ingest` |
| CHARX / BYAF | ✅ | ✅ | via `TavernKit::Ingest` (zip safety limits apply) |
| `.risum` modules | ✅ | ⏸️ | Deferred (see `docs/backlogs.md`) |

---

## 9. Memory System

TavernKit provides:
- `TavernKit::RisuAI::Memory::Base` interface
- `MemoryInput` / `MemoryResult` contracts
- middleware integration points

TavernKit does **not** ship a concrete memory algorithm (vector DB, summarizer).

---

## 10. Deferred / Out of Scope

| Feature | RisuAI | TavernKit | Reason |
|---------|--------|-----------|--------|
| UI rendering | ✅ | 🚫 | Gem has no UI |
| Storage/DB persistence | ✅ | 🚫 | App layer |
| Plugins / Lua hooks | ✅ | ⏸️ | Low priority |
| Full tokenizer suite | ✅ | ⏸️ | Interface-first |

---

## References

- RisuAI deltas/spec notes: `docs/compatibility/risuai-deltas.md`
- Core interface design: `docs/core-interface-design.md`
