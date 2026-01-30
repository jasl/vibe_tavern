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

### Dialect-aware behavior (:text vs chat)

SillyTavern uses two different prompt assembly modes:

- **Chat dialects** (e.g. `:openai`, `:anthropic`): prompt is assembled as an
  ordered collection of prompts/messages; **story string is not used**.
- **Text dialect** (`:text`): prompt is assembled as a single string; story
  string IS used as the primary "context template".

In Wave 4, the ST pipeline must branch based on `ctx.dialect`:

- `ctx.dialect == :text` => apply ContextTemplate story string rules
- otherwise => chat-style assembly (PromptManager-style)

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

In **text dialect mode** (`ctx.dialect == :text`):

- `anchorBefore` and `anchorAfter` MUST be derived from extension prompts:
  - `anchorBefore` := concatenation of `position: :before` injection content
  - `anchorAfter`  := concatenation of `position: :after` injection content
  - These are passed into `ContextTemplate#render` params as
    `anchorBefore` / `anchorAfter`.
  - Parity detail: each prompt string is trimmed, concatenated with `\n`, and
    the final anchor string is trimmed (no leading/trailing whitespace).
  - Note: they are NOT emitted as standalone blocks unless the template
    includes `{{anchorBefore}}` / `{{anchorAfter}}`.
- If `story_string_position == :in_chat`, emit the rendered story string as an
  in-chat message at `story_string_depth` with role `story_string_role`.
  - In instruct mode, do NOT apply `instruct.story_string_prefix/suffix`
    (chat message sequences already wrap the injected message).
- Otherwise (`:in_prompt` / `:before_prompt`), the rendered story string is
  used as system-level prompt prefix (and instruct may wrap it via
  `instruct.story_string_prefix/suffix`).
  - Note: in ST, `:before_prompt` behaves the same as `:in_prompt`; only
    `:in_chat` changes assembly behavior.

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

### Yield contract

`each` must yield `TavernKit::InjectionRegistry::Entry` objects (not raw tuples).

- When called without a block, it should return an Enumerator.
- Entry ids are strings (`entry.id`), so callers can do stable ordering,
  de-duplication, and tracing.

### Entry data structure

```ruby
TavernKit::InjectionRegistry::Entry = Data.define(
  :id,        # String - unique identifier for idempotent replacement
  :content,   # String - the text content to inject
  :position,  # Symbol - canonical position (:before, :after, :chat, :none)
  :role,      # Symbol - message role (:system, :user, :assistant)
  :depth,     # Integer - insertion depth for :chat position (0 = after last)
  :scan,      # Boolean - include in World Info scanning
  :ephemeral, # Boolean - one-shot, removed after generation
  :filter     # Proc or nil - optional (ctx) -> Boolean for conditional activation
)

# Convenience helpers:
entry.in_chat?      # position == :chat
entry.scan?         # include in World Info scanning
entry.ephemeral?    # one-shot
entry.active_for?(ctx)  # evaluates filter (if callable), else true
```

Notes:

- `position` is always stored as the canonical symbol (`:before`, `:after`, `:chat`,
  `:none`), even if an alias was used during registration.
- `filter` is called lazily during injection middleware; if it returns `false`, the
  entry is skipped for that build cycle (but remains registered).
  - Parity + safety: filter errors are treated as external input issues; injection
    middleware should `ctx.warn(...)` and treat the entry as active (unfiltered).
- `depth` is only meaningful when `position == :chat`; ignored otherwise.

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

## GroupContext Contract (Sync With Application Scheduling)

Group chat behavior spans **two** concerns:

- **Scheduling**: who should respond this turn (NATURAL/LIST/MANUAL/POOLED, swipe/continue/quiet overrides).
- **Prompt building**: how to merge cards / pick active character / apply group nudge.

Applications may want to own scheduling (UI queue, retries, concurrency), but
TavernKit needs the *same decision* to build the correct prompt. To avoid
drift when switching between “app decides” and “TavernKit decides”, Wave 4
standardizes a decision handshake.

### Config + Decision (single source of truth)

- **Config**: stable group settings (activation_strategy, generation_mode,
  allow_self_responses, disabled_members, etc.)
- **Decision**: one build-cycle result (activated member ids + why)

Contract shape (conceptual):

```ruby
# Stable config (persisted in chat/group metadata)
config = {
  activation_strategy: :natural, # :list/:manual/:pooled
  generation_mode: :swap,        # :append/:append_disabled
  disabled_members: [...],
  allow_self_responses: false,
}

# Per-turn decision (persisted per turn)
decision = {
  activated_member_ids: [12, 34],
  strategy: :natural,
  generation_type: :normal,
  is_user_input: true,
  seed: 123,              # determinism
  reasons: ["mention:Alice", "talkativeness:Bob"],
}
```

### Mode switching (A ⇄ B) without surprises

- **Mode A (TavernKit decides):**
  - app passes `config` + deterministic `seed` (and inputs like user text)
  - TavernKit computes `decision`
  - app persists `decision` for later debugging/replay
- **Mode B (app decides):**
  - app passes both `config` + `decision`
  - TavernKit uses `decision` for prompt building

### Validation (keep rules in sync)

If both an app-provided decision and a TavernKit-computed decision are
available, TavernKit should compare them:

- mismatch => `ctx.warn("group decision mismatch: ...")` (strict mode: raises)
- proceed with the **app-provided** decision (avoid surprising behavior)

Determinism requirements:

- Decision computation MUST accept an explicit `seed:` (or RNG injection),
  so “recompute and compare” is stable and debuggable.
- Both `config` and `decision` should have stable fingerprints recorded via
  `ctx.instrument(:stat, ...)` and/or `plan.trace`.

### Activation strategy contract (ST `group-chats.js`)

This section makes the 4 activation strategies implementable without
guesswork, based on ST staging `public/scripts/group-chats.js`.

Definitions:

- **enabled members** = `config.members` excluding `config.disabled_members`
- **banned member** = "last speaker" (prevents the same character speaking twice)
  - only applies when `allow_self_responses == false`
- **mention parsing** uses ST `extractAllWords()` semantics:
  - words = `/\b\w+\b/i` matches, lowercased
  - match if any word in `member.name` is present in the input words

Inputs required to compute a decision:

- `members`: ordered list of group member identifiers + display names + talkativeness
- `disabled_members`: list of identifiers
- `allow_self_responses`: boolean
- `generation_type`: `:normal`, `:continue`, `:swipe`, `:quiet`, `:impersonate`
- `activation_strategy`: `:natural`, `:list`, `:manual`, `:pooled`
- `is_user_input`: boolean (user typed text this turn)
- `activation_text`: String (user input if present; else last assistant message text)
- `last_speaker_id`: identifier (if known)
- `chat`: optional chat messages (needed for POOLED and swipe/continue parity)
- `seed`: integer (for RNG)

Pinned behavior:

- `:list`: activate all **enabled** members in list order.
- `:manual`:
  - if `is_user_input == true` => activate none (user message just sends)
  - else => pick 1 random enabled member
- `:pooled`:
  - Build `spoken_since_user` by walking chat backwards until the latest user
    message (or stop immediately if `is_user_input == true`), skipping system/narrator.
  - `have_not_spoken = enabled_members - spoken_since_user`
  - if `have_not_spoken.any?` => pick 1 random from it
  - else pick 1 random from enabled members, excluding `last_speaker_id` when possible
- `:natural`:
  1) mention activation: activate any mentioned enabled members (excluding banned member)
  2) talkativeness activation: iterate enabled members in a **shuffled order**
     (excluding banned member); activate if `talkativeness >= rng.rand`
  3) if still none, pick 1 random from `chatty_members` (talkativeness > 0) if any,
     else from all enabled members (excluding banned member)
  4) de-duplicate while preserving first-seen order

Generation-type overrides (applied before strategy):

- `:quiet`: pick 1 member using swipe-like logic that may allow system messages;
  if none can be determined, fall back to the first member.
- `:swipe` / `:continue`: pick member(s) using swipe-like logic that chooses the
  last speaking character; if that character is missing, this is an error.
- `:impersonate`: pick 1 random member.

Swipe selection (ST `activateSwipe`) contract:

- Input: `chat` (messages oldest→newest), `members`, `allow_system:` boolean, `seed` (for fallback random).
- The primary intent is: **select the last speaking group member**.
- Pinned behavior:
  - If the last chat message is from a group member (has `member_id`), select it.
  - Else (last message is user/system/narrator), scan backwards for the most
    recent message from a group member (ignoring user, and ignoring system when
    `allow_system == false`); select that `member_id`.
  - If no eligible member message exists, fall back to 1 random member.
  - Legacy compatibility: if a message lacks `member_id` but has a `name`, apps
    may map `name` to a member as a best-effort fallback (ST has a pre-update
    branch for this).

Determinism:

- All randomness (shuffle + random selection) MUST go through the injected RNG
  seeded by `decision[:seed]`.
- This is required so Mode A can be replayed and Mode B can be validated.

### Card merging contract (ST `generation_mode_join_prefix/suffix`)

When `generation_mode` is `:append` or `:append_disabled`, SillyTavern merges
multiple character cards into one "group card" used for prompt construction.

Wave 4 pins the ST join behavior from `getGroupCharacterCardsLazy()`:

- Only applies for `generation_mode` in `[:append, :append_disabled]`.
- Member selection:
  - Iterate members in `config.members` order.
  - Skip missing members.
  - If a member is disabled AND is not the current speaker AND mode is NOT
    `:append_disabled`, skip it.
  - Otherwise include it (including a disabled current speaker).
- Join templates:
  - `join_prefix` and `join_suffix` are applied **per member field value**.
  - Both support `<FIELDNAME>` placeholder (case-insensitive) replaced with the
    display name of the field (e.g. `"Description"`, `"Scenario"`).
- Normalization:
  - Each field value is `strip`ped; empty values are ignored.
  - The final output joins member chunks with `"\n"`.
- Field-specific rules:
  - `scenario`: if an app-provided override exists (ST `chat_metadata.scenario`),
    use it (after trim) instead of collecting from members.
  - `example messages`:
    - if an override exists (ST `chat_metadata.mes_example`), use it
    - else collect member `mes_examples`, and ensure each non-empty value starts
      with `"<START>\n"` (prepend if missing) before applying join templates.

`baseChatReplace()` substitutions exist in ST, but Wave 4 only requires the
structural join behavior above; macro expansion still happens later in Stage 7.

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
  - Dialect-aware:
    - `ctx.dialect == :text`: `:before/:after` injections feed `anchorBefore/anchorAfter` only (template decides inclusion)
    - otherwise: `:before/:after` injections are emitted as relative blocks at start/end (chat-style)
  - Merge `position: :chat` entries by `(depth, role)` (stable order within group)
  - Final in-chat ordering for the same depth is role-descending: Assistant > User > System (ST parity via reverse-depth insertion)
  - If a merged group is empty after trimming/normalization, do not emit a message for it
```

#### Author's Note insertion (ST `2_floating_prompt`) parity

SillyTavern's Author's Note extension (`public/scripts/authors-note.js`)
computes a per-turn "should inject" boolean based on the number of **user**
messages and the configured `note_interval`.

Wave 4 contract:

- Inputs:
  - `preset.authors_note` (String)
  - `preset.authors_note_frequency` (Integer, ST `note_interval`)
  - `ctx.turn_count` (Integer) — **number of user messages** in the chat **including**
    the current user input (application is responsible for setting it correctly)
- Scheduling:
  - if `authors_note_frequency <= 0` => disabled (no injection)
  - else inject when `ctx.turn_count > 0` AND `ctx.turn_count % authors_note_frequency == 0`
    - parity note: ST computes a countdown UI, but the "inject now" condition is
      equivalent to "turn count is a multiple of interval" (for `turn_count > 0`)
- Content:
  - When injected, note content is `preset.authors_note.to_s` (may be empty).
  - If the note content is empty/whitespace after normalization, do not emit a message.
- Placement:
  - Uses `preset.authors_note_position` (`:in_chat`, `:in_prompt`, `:before_prompt`, `:none`)
  - Uses `preset.authors_note_depth` / `preset.authors_note_role`
  - `ctx.authors_note_overrides` (if present) may override **position/depth/role**
    for this build cycle (but not text/frequency).

Rationale: this makes Author's Note deterministic and testable while matching
the ST insertion cadence.

#### Persona description positions parity (ST `persona_description_positions`)

SillyTavern supports 5 persona description positions. Wave 4 pins the exact
interaction with Author's Note to avoid "almost correct" implementations.

Inputs (conceptual; app supplies them in some form):
- `persona_text` (String)
- `persona_position` (Symbol): `:in_prompt`, `:top_an`, `:bottom_an`, `:at_depth`, `:none`
- `persona_depth` (Integer, only for `:at_depth`)
- `persona_role` (Symbol, only for `:at_depth`)

Behavior:

- `:none` => do nothing.
- `:in_prompt` => persona text is emitted as part of the system prompt
  (implementation detail: typically the `persona_description` pinned slot).
- `:at_depth` => persona text becomes an in-chat injection at `persona_depth`
  with role `persona_role`, and MUST have WI scanning enabled (ST passes
  `allowWIScan=true` when creating the depth injection).
- `:top_an` / `:bottom_an` => **only** applies on turns where Author's Note is
  scheduled to inject (see Author's Note scheduling contract above).
  - When Author's Note is injected, its content is rewritten to include persona:
    - `:top_an`    => `"#{persona_text}\n#{authors_note_text}"`
    - `:bottom_an` => `"#{authors_note_text}\n#{persona_text}"`
  - When Author's Note is NOT injected this turn, persona MUST NOT be injected
    at all (no separate message).

This mirrors ST's implementation (`addPersonaDescriptionExtensionPrompt()`),
where persona TOP/BOTTOM is applied by rewriting the Author's Note extension
prompt only when `shouldWIAddPrompt` is true.

#### In-chat insertion (ST `doChatInject()` parity)

SillyTavern's reference implementation lives in `public/script.js#doChatInject()`.

Contract:

- **Depth semantics:** depth is measured from the end of chat history.
  - depth `0` = after the last message
  - depth `N` = before the Nth-to-last message
  - depth is clamped: inserting deeper than the chat length inserts at the start.
- **Continue special-case:** when `ctx.generation_type == :continue`, depth `0`
  injections behave as if depth `1` (avoids injecting *after* the continued message).
- **Role ordering:** for the same depth, the final in-chat order is:
  `:assistant` → `:user` → `:system`.
  - In ST this comes from inserting `[system, user, assistant]` into a reversed
    chat buffer and then reversing back.
- **Stable concatenation within a role:** for a given `(depth, role)`:
  - sort entries by `entry.id` lexicographically
  - join `entry.content.strip` with `"\n"`
  - do NOT append a trailing newline (message formatting later handles wrapping)

Pseudocode (conceptual):

```ruby
effective_depth = (ctx.generation_type == :continue && depth == 0) ? 1 : depth
content = entries.sort_by(&:id).map { |e| e.content.strip }.reject(&:empty?).join("\n")
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
