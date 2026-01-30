# Wave 4 Contracts (Orchestration & Output Layer)

Date: 2026-01-30

This document "pins down" Wave 4 behavior so implementation stays aligned with:

- `docs/plans/2026-01-29-tavern-kit-rewrite-roadmap.md` (work checklist)
- SillyTavern staging behavior (reference only; no test/fixture copying)
- Our pipeline philosophy: tolerant at external input boundaries, fail-fast for programmer errors

## Definitions

- **External input**: anything coming from JSON/PNG imports, user messages, chat history loaded from disk, or 3rd-party extensions.
- **Programmer error**: bugs in TavernKit itself or in downstream custom middleware/hooks.

## Strict Mode / Debug Mode (Standardized)

TavernKit uses two orthogonal switches:

- **Strict mode**: `ctx.strict = true` (or DSL `strict(true)`).
  - `ctx.warn("...")` raises `TavernKit::StrictModeError`.
  - Intended for tests + debugging only.
- **Debug instrumentation**: `ctx.instrumenter = Prompt::Instrumenter::TraceCollector.new` (or DSL `instrumenter(...)`).
  - When instrumenter is `nil` (default), debug work must be near-zero overhead.
  - Middleware must rely on `ctx.instrument(...)` with lazy payload blocks when expensive.

Policy:

- For external input, prefer `ctx.warn` + best-effort output (preserve raw tokens if needed).
- For programmer errors, raise (let `Prompt::Middleware::Base` wrap with `PipelineError(stage: ...)`).

## Prompt::Message Contract (Tool/Function Calling)

Core message object is `TavernKit::Prompt::Message`:

- `role`: Symbol (`:system`, `:user`, `:assistant`, `:tool`, `:function`, ...)
- `content`: String (dialects may later map to provider content blocks)
- `attachments`: optional Array (reserved for multimodal)
- `metadata`: optional Hash (reserved for dialect/tooling passthrough)

### Standard metadata keys (Core-level convention)

To keep Core agnostic but still support tool calling across providers, Wave 4
standardizes a *small* set of keys. Dialects must read these keys and map them
to the provider format.

- `metadata[:tool_calls]`: Array<Hash>
  - Present on an assistant message that triggers tool/function calls.
  - Matches OpenAI "tool_calls" shape closely:
    - each call: `{ id:, type: "function", function: { name:, arguments: } }`
- `metadata[:tool_call_id]`: String
  - Present on a tool result message, linking it to a previous call id.
- `metadata[:signature]`: String (optional)
  - SillyTavern adds a signature field to support tool-call provenance.

Notes:

- Key types in `Message#metadata` are allowed to be Symbol or String, but Core
  code should prefer Symbol keys for anything it owns.
- Any other metadata keys are dialect-specific and may be ignored by default.

## Dialects Contract

Dialects convert `Array<Prompt::Message>` into provider request payload shapes.

Entry point (planned):

```ruby
TavernKit::Dialects.convert(messages, dialect: :openai, **opts)
```

### OpenAI dialect (ChatCompletions)

Output: `Array<Hash>` where each hash contains:

- `role` (String)
- `content` (String or Array for multimodal in the future)
- optional `name`
- optional `tool_calls` (from `message.metadata[:tool_calls]`)
- optional `tool_call_id` (for `role == "tool"`, from `message.metadata[:tool_call_id]`)
- optional `signature` (from `message.metadata[:signature]`)

### Anthropic dialect (messages + system)

Output: `{ system:, messages: }` where:

- system content is separated (if present)
- message content may be mapped to content blocks
- tool use / tool result blocks must be derived from the same standardized keys
  (`:tool_calls`, `:tool_call_id`) without requiring ST-specific objects

### Dialect extensibility

Keep it simple:

- Dialects are addressed by Symbol (`:openai`, `:anthropic`, ...)
- Adding a new dialect should be possible without modifying Core internals,
  e.g. a registry map inside `TavernKit::Dialects`.

## Trimmer Contract

Trimmer operates on `Array<Prompt::Block>` and enforces a token budget by
disabling blocks in-place (returns modified copies, does not remove).

### Budget rule (SillyTavern)

SillyTavern uses the same budgeting rule as ST's `ChatCompletion.setTokenBudget(context, response)`:

- `context_window_tokens` = model context window (ST: `openai_max_context`)
- `reserved_response_tokens` = reserved output tokens (ST: `openai_max_tokens`)
- `max_prompt_tokens = context_window_tokens - reserved_response_tokens`

In TavernKit these live on `TavernKit::SillyTavern::Preset` and are imported by
`TavernKit::SillyTavern::Preset::StImporter`.

`strategy: :group_order` (ST default):

- Eviction priority: `:examples` -> `:lore` -> `:history`
- `:system` is never evicted
- **Examples are evicted as whole dialogues**
- History is evicted oldest-first, but **must preserve the latest user message**

`strategy: :priority` (RisuAI default):

- Sort by `block.priority` ascending, evict lowest first
- `removable: false` blocks are never evicted

### Bundled eviction (examples-as-dialogues)

Wave 4 introduces a Core-level convention for "evict as a unit":

- `block.metadata[:eviction_bundle]` (String)
  - blocks sharing the same bundle id must be enabled/disabled together
  - intended for ST example dialogues and similar grouped content

If a bundle is evicted, each block still gets an `EvictionRecord` (for
observability), but the reason should indicate group eviction, e.g.
`:group_overflow`.

### Failure mode (mandatory prompts exceed budget)

Default behavior (chosen): **error** (`TavernKit::MaxTokensExceededError`).

If, after evicting every eligible block (i.e. `removable: true` and evictable by
strategy), the prompt is still above budget, the trimming stage must raise
`TavernKit::MaxTokensExceededError` (do not silently disable protected blocks).

Error params mapping (for consistency with MaxTokensMiddleware):
- `stage:` `:trimming`
- `max_tokens:` `context_window_tokens`
- `reserve_tokens:` `reserved_response_tokens`
- `estimated_tokens:` estimated prompt tokens after the final trimming attempt

### Observability

Trimmer must produce:

- `TavernKit::TrimResult` (kept/evicted arrays + report)
- `TavernKit::TrimReport` with per-block `EvictionRecord`

SillyTavern trimming middleware should attach `trim_report` to `ctx.trim_report`
and instrument summary stats (initial/final/budget, eviction_count).

## SillyTavern ContextTemplate (Story String) Contract

SillyTavern has a "story string" (ContextTemplate) used to assemble prompt
text from multiple fields.

Core object: `TavernKit::SillyTavern::ContextTemplate`.

### Template syntax

Wave 4 only relies on a restricted Handlebars-like subset:

- `{{field}}` substitution for known fields
- `{{#if field}}...{{/if}}` conditional blocks
- `{{#unless field}}...{{/unless}}` negative conditional blocks

Unknown `{{macro}}` placeholders must be preserved so Stage 7 MacroExpansion
can expand them (tolerant mode).

### Output normalization

ST behavior (and our renderer) normalizes the rendered output:

- Trim trailing whitespace.
- If non-empty, ensure it ends with `\n`.

### Injection behavior

ContextTemplate includes `story_string_position`, `story_string_depth`, and
`story_string_role` (mirrors ST `extension_prompt_types` / `extension_prompt_roles`).

- If `story_string_position == :in_chat`, emit an in-chat message at
  `story_string_depth` with role `story_string_role`.
  - In instruct mode, do NOT apply `instruct.story_string_prefix/suffix`
    (chat message sequences already wrap the injected message).
- Otherwise (`:in_prompt` / `:before_prompt`), treat the story string as
  system-level prompt content at the corresponding position, and instruct
  may wrap it via `instruct.story_string_prefix/suffix`.

## InjectionRegistry Contract

`InjectionRegistry::Base` defines the interface for runtime content injection (mirrors
STscript `/inject` feature).

### Interface

```ruby
class TavernKit::InjectionRegistry::Base
  def register(id:, content:, position:, **opts) = raise NotImplementedError
  def remove(id:) = raise NotImplementedError
  def each(&block) = raise NotImplementedError
  def ephemeral_ids = raise NotImplementedError
end
```

### Standard opts keys

When calling `register(id:, content:, position:, **opts)`, the following opts are
recognized:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `role` | Symbol | `:system` | Message role (`:system`, `:user`, `:assistant`) |
| `depth` | Integer | `4` | Insertion depth (0 = after last message, N = before Nth-to-last). ST default is 4. |
| `scan` | Boolean | `false` | Include in World Info scanning |
| `ephemeral` | Boolean | `false` | One-shot: removed after generation |
| `filter` | Proc/nil | `nil` | Optional closure `(ctx) -> Boolean` for conditional activation |

### Position mapping

`position:` parameter maps to ST `extension_prompt_types`. For ST parity, the
canonical positions are:

- `:before` (ST `/inject position=before`)
- `:after` (ST `/inject position=after`, default)
- `:chat` (ST `/inject position=chat`)
- `:none` (ST `/inject position=none`)

Aliases are allowed for convenience:

- `:before_prompt` => `:before`
- `:in_prompt` => `:after`
- `:in_chat` => `:chat`

| TavernKit position | ST `/inject` arg | ST constant | Behavior |
|--------------------|------------------|-------------|----------|
| `:none` | `none` | `NONE (-1)` | WI scanning only, not in prompt |
| `:after` | `after` | `IN_PROMPT (0)` | In prompt, after main prompt (still before chat history) |
| `:chat` | `chat` | `IN_CHAT (1)` | In chat, at specified depth |
| `:before` | `before` | `BEFORE_PROMPT (2)` | Before main prompt (system-level) |

### Idempotency

Registering with an existing `id:` replaces the previous entry (no duplicates).

### Ordering

`each` must yield entries in a stable order.

For ST parity, the default implementation should iterate in lexicographic `id`
order (ST sorts extension prompt keys before concatenation).

### Ephemeral lifecycle

Entries with `ephemeral: true`:
- Are returned by `ephemeral_ids` after each generation
- Should be removed by the application layer post-generation
- TavernKit does NOT auto-remove (Rails controls lifecycle)

## HookRegistry Contract

`HookRegistry::Base` defines the interface for before/after build hooks.

### Interface

```ruby
class TavernKit::HookRegistry::Base
  def before_build(&block) = raise NotImplementedError
  def after_build(&block) = raise NotImplementedError
  def run_before_build(ctx) = raise NotImplementedError
  def run_after_build(ctx) = raise NotImplementedError
end
```

### Hook context

Hooks receive `ctx` (Prompt::Context) directly:

- `before_build` hooks: may mutate `ctx.character`, `ctx.user`, `ctx.preset`,
  `ctx.history`, `ctx.user_message`, `ctx.macro_vars`
- `after_build` hooks: may mutate `ctx.plan` (add/remove/modify blocks)

Hooks should NOT:
- Mutate `ctx.blocks` directly in `before_build` (use middleware instead)
- Raise exceptions for recoverable issues (use `ctx.warn`)

### Execution order

Hooks run in registration order (FIFO).

## Middleware Data Flow Contract

Each middleware stage has defined inputs and outputs. Stages run in order 1→9.
The `:hooks` middleware wraps the pipeline and runs `before_build` hooks in its
`before(ctx)` phase and `after_build` hooks in its `after(ctx)` phase.

### Stage 1: Hooks

```
Name: :hooks
Input (before):  ctx.hook_registry, ctx.character, ctx.user, ctx.preset, ctx.history
Output (before): (hooks may mutate ctx inputs)
Side effects (before): Runs all registered before_build hooks
Invariant (before): Must NOT modify ctx.blocks

Input (after):  ctx.hook_registry, ctx.plan
Output (after): (hooks may mutate ctx.plan)
Side effects (after): Runs all registered after_build hooks
```

### Stage 2: Lore

```
Name: :lore
Input:  ctx.lore_books, ctx.lore_engine, ctx.scan_messages, ctx.scan_context,
        ctx.scan_injects, ctx.forced_world_info_activations, ctx.generation_type
Output: ctx.lore_result (Lore::Result), ctx.outlets (Hash{String => content})
Side effects: Evaluates World Info via ST Lore::Engine
Invariant: Does NOT modify ctx.blocks
```

### Stage 3: Entries

```
Name: :entries
Input:  ctx.preset.effective_prompt_entries, ctx.lore_result, ctx.generation_type,
        ctx.chat_scan_messages, ctx.turn_count
Output: ctx.prompt_entries (Array<PromptEntry> - filtered and normalized)
Side effects: Applies FORCE_RELATIVE_IDS, FORCE_LAST_IDS normalization
Behavior:
  - Filter entries by conditions (active_for?(ctx))
  - Apply ST entry ID normalization rules
```

### Stage 4: PinnedGroups

```
Name: :pinned_groups
Input:  ctx.prompt_entries, ctx.character, ctx.user, ctx.preset, ctx.lore_result
Output: ctx.pinned_groups (Hash{String => Array<Block>})
Side effects: Resolves 14 ST pinned group slots
Slots: main_prompt, persona_description, character_description, character_personality,
       scenario, chat_examples, chat_history, authors_note, world_info_before,
       world_info_after, system_prompt, jailbreak, post_history_instructions, etc.
```

### Stage 5: Injection

```
Name: :injection
Input:  ctx.injection_registry, ctx.pinned_groups, ctx.preset, ctx.authors_note_overrides
Output: ctx.blocks (Array<Block> - with injections applied)
Side effects: Applies injection registry entries, author's note, persona description
Behavior:
  - Map injection positions to insertion points
  - Apply extension_prompt_types mapping
  - Handle author's note interval logic (note_interval)
  - Handle persona description positions (IN_PROMPT/TOP_AN/BOTTOM_AN/AT_DEPTH/NONE)
  - Merge `position: :chat` entries by `(depth, role)` (stable order within group)
  - Final in-chat ordering for the same depth is role-descending: Assistant > User > System (ST parity via reverse-depth insertion)
  - If a merged group is empty after trimming/normalization, do not emit a message for it
```

### Stage 6: Compilation

```
Name: :compilation
Input:  ctx.pinned_groups, ctx.prompt_entries, ctx.outlets, ctx.blocks
Output: ctx.blocks (Array<Block> - fully compiled)
Side effects: Compiles all entries into blocks, resolves outlet insertions
Behavior:
  - Expand pinned groups into block array
  - Resolve outlet `{{slot::name}}` insertions from ctx.outlets
  - Set token_budget_group on each block
  - Set removable flag based on entry/slot requirements
```

### Stage 7: MacroExpansion

```
Name: :macro_expansion
Input:  ctx.blocks, ctx.expander, ctx.macro_vars, ctx.macro_registry
Output: ctx.blocks (Array<Block> - content expanded)
Side effects: Expands {{macro}} syntax in all block content
Behavior:
  - Use ST Macro::V2Engine (or V1 fallback)
  - Build environment from ctx (character, user, preset, history, etc.)
  - Preserve unknown macros (tolerant mode)
  - Record macro errors as warnings (strict mode: raise)
```

### Stage 8: PlanAssembly

```
Name: :plan_assembly
Input:  ctx.blocks, ctx.outlets, ctx.greeting_index, ctx.generation_type,
        ctx.resolved_greeting, ctx.preset
Output: ctx.plan (Prompt::Plan)
Side effects: Creates final Plan with blocks, greeting, outlets, warnings
Behavior:
  - Handle continue mode: nudge prompt, prefill, postfix (NONE/SPACE/NEWLINE/DOUBLE_NEWLINE)
  - Handle impersonate mode: impersonation_prompt, assistant_impersonation (Claude)
  - Set assistant prefill for Claude sources
  - Populate plan.warnings from ctx.warnings
```

### Stage 9: Trimming

```
Name: :trimming
Input:  ctx.plan, ctx.token_estimator, ctx.preset (budget fields)
Output: ctx.plan (trimmed), ctx.trim_report (TrimReport)
Side effects: Enforces token budget, populates trim_report
Behavior:
  - Delegate to Core Trimmer with strategy selected by the pipeline
  - Default strategy is fixed by pipeline: :group_order (ST), :priority (RisuAI)
  - Respect eviction_bundle for grouped eviction
  - Raise `MaxTokensExceededError` if budget cannot be met (mandatory prompts exceed limit)
  - Instrument: initial_tokens, final_tokens, budget_tokens, eviction_count
```

## Middleware Output Expectations (Wave 4)

Wave 4 middleware must output blocks that are ready for trimming and dialect conversion:

- `Prompt::Block#token_budget_group` is set (`:system`, `:examples`, `:lore`, `:history`, ...)
- `Prompt::Block#removable` is set correctly (protect hard-required content)
- `Prompt::Block#message_metadata` is used for tool/function passthrough when needed

Stage naming:

- All ST pipeline stages must have stable names (symbols) via Pipeline entry names.
- Exceptions bubble; Base middleware wraps them into `PipelineError(stage: ...)`.
