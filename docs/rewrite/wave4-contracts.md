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

Default behavior (chosen): **error**.

If, after evicting every eligible block (i.e. `removable: true` and evictable by
strategy), the prompt is still above budget, the trimming stage must raise an
error (do not silently disable protected blocks).

### Observability

Trimmer must produce:

- `TavernKit::TrimResult` (kept/evicted arrays + report)
- `TavernKit::TrimReport` with per-block `EvictionRecord`

SillyTavern trimming middleware should attach `trim_report` to `ctx.trim_report`
and instrument summary stats (initial/final/budget, eviction_count).

## Middleware Output Expectations (Wave 4)

Wave 4 middleware must output blocks that are ready for trimming and dialect conversion:

- `Prompt::Block#token_budget_group` is set (`:system`, `:examples`, `:lore`, `:history`, ...)
- `Prompt::Block#removable` is set correctly (protect hard-required content)
- `Prompt::Block#message_metadata` is used for tool/function passthrough when needed

Stage naming:

- All ST pipeline stages must have stable names (symbols) via Pipeline entry names.
- Exceptions bubble; Base middleware wraps them into `PipelineError(stage: ...)`.
