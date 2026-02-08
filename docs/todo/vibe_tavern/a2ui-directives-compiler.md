# TODO: A2UI Support via Structured Directives (Compiler Plan)

Goal: support Google A2UI as an **optional UI rendering backend** for VibeTavern,
without making the LLM generate A2UI directly.

This is a product-facing backlog item. It depends on (and builds on) the
protocol/reliability work already documented in:

- Structured directives: `docs/research/vibe_tavern/directives.md`
- Architecture overview: `docs/research/vibe_tavern/architecture.md`
- A2UI reference source: `resources/A2UI/` (upstream repo checkout)

## Why A2UI (and why compile instead of generating A2UI)

A2UI is a declarative, streaming UI protocol:

- server → client is a **JSONL stream**
- each line is one JSON object with **exactly one** message key:
  `beginRendering`, `surfaceUpdate`, `dataModelUpdate`, or `deleteSurface`
- the client renders by buffering per-surface component/data updates until
  `beginRendering` is received

Key point for reliability:

- A2UI v0.8 is optimized for “structured output LLMs”, but the protocol payload
  is still large and nested (component wrappers, explicit child lists, typed
  dataModel adjacency lists).
- For multi-provider production, letting the LLM generate *full A2UI* is a large
  reliability tax.

So the recommended path is:

1) LLM emits **high-level directives** (small, stable schema)
2) App executes directives, updating **strong-fact state** (domain + UI state)
3) A deterministic compiler renders that state into **A2UI messages**

This keeps the “LLM output protocol” small, and keeps A2UI complexity inside
tested code.

## Fit with current VibeTavern architecture

Current infra boundaries (already implemented):

- Single request boundary: `lib/tavern_kit/vibe_tavern/prompt_runner.rb`
- Directives protocol + fallbacks:
  - `lib/tavern_kit/vibe_tavern/directives/schema.rb`
  - `lib/tavern_kit/vibe_tavern/directives/parser.rb`
  - `lib/tavern_kit/vibe_tavern/directives/validator.rb`
  - `lib/tavern_kit/vibe_tavern/directives/runner.rb`
- Tool calling loop (separate protocol, side effects):
  - `lib/tavern_kit/vibe_tavern/tool_calling/tool_loop_runner.rb`

Important constraint:

- `lib/tavern_kit/vibe_tavern` is infrastructure; it should not hardcode
  product-specific directive types, UI templates, or component catalogs.
  Those belong to the app layer (injected registries/presets).

## What “A2UI support” means in VibeTavern terms

We need three layers (explicitly separated):

1) **Directive layer (LLM-facing)**
   - directive types are app-defined
   - infra provides parsing/validation/fallbacks
2) **UI IR (strong-fact state)**
   - deterministic, inspectable representation of what the UI should show
   - updated by directive execution and/or tool results
3) **A2UI backend**
   - compiles UI IR → A2UI JSONL messages
   - validates and size-limits messages (defense-in-depth)

A2UI should remain *optional*:

- Another backend might render directly to your own UI macros, or to HTML/JSON
  for a specific client.
- The directive protocol stays stable either way.

## Key A2UI v0.8 protocol facts we must preserve

These become hard validation rules (not “best effort”):

- Message shape:
  - JSON object
  - exactly one top-level key:
    `beginRendering`, `surfaceUpdate`, `dataModelUpdate`, or `deleteSurface`
- Surface scoping:
  - every message targets a `surfaceId`
  - state is per-surface (component buffer + data model)
- Ordering:
  - `beginRendering` must come after at least one `surfaceUpdate` for that surface
  - other ordering is flexible, but the recommended order is:
    `surfaceUpdate` → `dataModelUpdate` → `beginRendering`
- Component updates:
  - adjacency list: flat component array + ID references
  - each component’s `component` wrapper must contain **exactly one** component type key
- Data model updates:
  - `dataModelUpdate.contents` is a typed adjacency list:
    each entry has `key` + exactly one of:
    `valueString`, `valueNumber`, `valueBoolean`, `valueMap`
  - If `dataModelUpdate.path` is omitted (or `/`), `contents` replaces the
    entire surface data model (root replace).
  - arrays are not first-class in `contents` in v0.8, so list-like UI needs an
    explicit strategy (see “Data model arrays”)

All of these rules are described in the A2UI repo:

- `resources/A2UI/docs/reference/messages.md`
- `resources/A2UI/specification/v0_8/docs/a2ui_protocol.md`
- `resources/A2UI/specification/v0_8/json/server_to_client.json`

## Hard problems / risks (and how to de-risk them)

### 1) Input binding (draft vs committed) and “who owns the data model”

A2UI’s interactive components use **data binding**. In typical A2UI renderers,
user input can update the client-side data model *before* any message is sent
back to the server (until an action is triggered).

This creates a classic “draft vs committed” conflict:

- server may push a `dataModelUpdate` while the user is editing
- client may implicitly mutate state via bound inputs
- naive “replace root data model” updates can clobber user edits

Recommended hard rules (P0):

- Treat the server as the **source of truth** for committed state.
- Reserve a draft namespace for in-flight user edits.
  - Example namespaces:
    - `/draft/...` — user-editable, not authoritative until submit
    - `/committed/...` — authoritative domain state
- Avoid sending root-replacing `dataModelUpdate` while a surface is “editing”.
  - Prefer narrow patches or action-driven updates (submit/next).

This rule also helps our non-A2UI Rails host: it keeps “what the user is
editing” separate from “what the system believes is true”.

### 2) Default values: avoid `path + literal*` implicit writes

A2UI allows a BoundValue to include both a `path` and a `literal*` value. Many
renderers treat this as “initialize this path with the literal, then bind”.

This is hostile to “strong-fact state” because the mutation happens on the
client, not the server.

Recommended hard rules (P0):

- Compiler must **not** emit BoundValue shorthands that include both `path` and
  `literal*`.
- All defaults must be applied via explicit `dataModelUpdate` sent by the server
  (auditable/replayable).

### 3) Safety: “data not code” is necessary but not sufficient

Even as pure data, A2UI can DoS a client if we allow unbounded output.

Guardrails to implement in the compiler (and validate again at the boundary):

- max messages per response
- max bytes per message / per surface / per response
- max component count per surface
- max data model depth / entry count / string bytes
- strict allowlist of component types (catalog-driven)
- strict allowlist of allowed actions (button/event names) and context keys
- rich text / URLs:
  - P0: treat all user-visible strings as plain text (no HTML/Markdown execution)
  - if/when we render rich text or links: sanitize output and restrict URL schemes
    (e.g. http/https only; never `javascript:`)

### 4) Version drift (A2UI evolves)

The A2UI repo includes v0.8 (stable) and newer draft specs (v0.9+).

Compiler approach reduces risk:

- the LLM never sees the A2UI version or exact shape
- version upgrades are internal: swap compiler target + renderer

Decision (recommended):

- Pin to A2UI v0.8 first (stable), and only add v0.9+ once we have a concrete
  renderer and a migration reason.

Migration triggers (make this an explicit checklist, not a vibe):

- We need first-class nil/delete semantics in the UI data model.
- We need true JSON arrays/lists in the A2UI data model (not map-encoded lists).
- We want simpler server→client data model updates (v0.9 moves away from typed
  adjacency lists toward more standard JSON object updates).
- We have a renderer/client that commits to v0.9 and we can validate end-to-end
  (ClientSim + replay + production canary).

### 5) Path canonicalization (pointer vs segment)

The A2UI docs and examples are inconsistent about whether paths are full JSON
Pointers (`/draft/name`) or relative/segment paths (`draft` / `user`).

If we do not canonicalize, different renderers (or future backends) will
interpret the same “path” differently, causing silent state drift.

Recommended hard rules (P0):

- UI IR uses **JSON Pointer** everywhere.
  - Always starts with `/`
  - Escape rules follow RFC 6901 (`~` / `/` encoding)
- Compiler accepts both pointer and segment paths at the boundary, but
  canonicalizes to pointer internally.
- Event ingress (client → server) applies the same canonicalization rules.

Important exception (template scopes):

- A2UI data binding supports “scoped paths” inside templates/dynamic lists.
  In that context, `/name` is relative to the current item scope (not the
  surface root).
- Canonicalization should therefore be **syntax-only** (RFC 6901), while path
  **resolution** must be scope-aware.
- P0 recommendation: do not enable dynamic list templates until we implement a
  scope-aware resolver. Prefer `explicitList` children for initial templates.

### 6) Data model arrays (v0.8 typed adjacency list)

`dataModelUpdate.contents` supports strings/numbers/booleans/maps, not arrays.

Strategies (choose one explicitly; don’t let this drift):

- **No arrays (initial)**: represent lists as fixed UI components (explicit children)
- **Encode arrays as maps**: keys `"0"`, `"1"`, ... and define stable ordering semantics
- **Custom catalog component**: e.g. `Repeater`/`TagList` that expects a map-like structure

If we use “map-encoded lists”, the ordering semantics must be part of the contract:

- keys must be decimal integer strings (`"0"`, `"1"`, ...)
- iteration order is numeric ascending
- define whether sparse indexes are allowed (recommended: disallow in P1)
- define insertion/deletion semantics (otherwise you only safely support append)

Array roadmap (recommended):

- P0: UI collects list-ish input as strings (tags input / comma-separated),
  server normalizes to JSON arrays in domain state on submit.
- P1: introduce a compiler-supported list encoding (map-indexed list or a custom
  component) for dynamic lists and multi-select patterns.

### 7) Nil/deletion semantics (v0.8)

Typed adjacency lists in v0.8 do not provide a clean, standard “delete key /
set null / rollback” story.

We must define a deterministic contract for:

- user clears a field (non-empty → empty)
- user re-fills a cleared field
- optional fields omitted vs intentionally cleared

Recommended strategy:

- P0 (most compatible): do not attempt “delete” in the v0.8 data model.
  - Normalize cleared values in draft UI state (e.g. empty string).
  - Convert empty-string/empty-value back to nil/deletion at the domain boundary
    on submit (app-specific).
  - Prefer full surface rebuild/re-init when we must remove fields from the
    client data model.
- P1 (stronger): implement deletions via surface reset.
  - Represent deletions in UI IR (e.g. tombstones), and when detected:
    `deleteSurface(surfaceId)` + full rebuild to guarantee keys disappear.
- Future: revisit once we target v0.9+ (remove semantics are clearer).

Minimum tests to add (CI):

- field transitions: value → cleared → value (submit payload consistent)
- nil strategy: UI IR with nil values compiles deterministically (warnings ok)
- surface reset path: tombstone triggers deleteSurface + rebuild (P1)

### 8) Event handling / round-trips (client → server)

A2UI defines `userAction` (client → server) as the primary interaction message.

We need an app-level contract:

- which UI actions map to which server endpoints
- whether an action triggers:
  - a directives-only run (fast path), or
  - a tool loop (side effects), or
  - a hybrid: tool loop then directives finalization

This should be treated like tool calling:

- deterministic envelope shape for actions
- strict validation of action names/context
- bounded payload sizes

Recommended implementation details (P0):

- Accept only A2UI-style event envelopes:
  - exactly one of: `userAction` or `error`
- `userAction` must be validated:
  - action name allowlist
  - surfaceId and sourceComponentId format (bounded length, safe charset)
  - context size/depth limits (DoS defense)
- Stale event protection:
  - validate `surfaceId` epoch/version is still current
  - reject stale surface actions with a recoverable message (“UI expired, regenerate”)
- Web security (Rails host):
  - normal Rails session/CSRF checks still apply
  - include a per-surface nonce (stored in UI IR and rendered into the UI);
    require it on ingress to reduce action spoofing
  - keep action contexts small and scalar-first; avoid accepting arbitrary objects
- `error` events should be treated as signals to trigger recovery policies
  (see next sections).

Renderer contract (our product, P0):

- User input updates client-local draft state only (`/draft/...`).
- Do not emit “per-keystroke” server events. Only explicit actions (submit/next)
  send a `userAction` back to the server.
- `userAction.context` should contain only the minimal submitted payload needed
  for the action (scalar-first; avoid arbitrary objects).
- This contract should be consistent across hosts:
  - Rails HTML host: normal forms update local DOM state; submit posts once.
  - A2UI host: draft binding updates local client model; submit sends `userAction`.

Optional future extension (P1): optimistic concurrency (`surface_rev`)

- Track a monotonically increasing `surface_rev` per surface (separate from
  epoch/version used for resets).
- Include `surface_rev` in the UI (hidden field / bound value) and require it
  on ingress; reject stale revs with a recoverable “UI out of date” response.

### 9) Failure & recovery policy (don’t leave stale UI behind)

If a surface compilation/validation fails and we silently drop updates, the
client may keep rendering an old surface, and the user might keep interacting
with stale UI.

We need explicit recovery strategies:

1) **Soft fail**: fall back to plain text (does not modify existing surfaces)
2) **Surface fail**: emit `deleteSurface(surfaceId)` then fall back (prevents
   further interaction with stale UI)
3) **Epoch reset**: rotate surfaceId epoch/version (e.g. `main#e=2`) and re-send
   a full initialization (most robust)

Strict vs best-effort (recommended):

| Dimension | Strict (dev/test) | Best-effort (production) |
| --- | --- | --- |
| Primary goal | Catch compiler/validator bugs early | Keep the conversation moving safely |
| Coercions | Reject non-canonical/ambiguous inputs | Coerce where safe (canonicalize paths, normalize patch ops) and log warnings |
| Invalid A2UI | Fail the surface/turn (raise) | Never emit invalid A2UI; surface fail (`deleteSurface`) then safe fallback |
| Stale UI risk | Prefer loud failures | Prefer delete/reset over silent drops |

### 10) Renderer compatibility: “reset escape hatch”

Some A2UI renderers in the wild do not correctly apply incremental updates to
existing surfaces.

We should plan for a “reset escape hatch”:

- Each surface has a lifecycle and an epoch/version.
- Triggers for epoch reset:
  - client sends `error`
  - semantic validator detects a severe invariant violation
  - production monitoring detects “updates not applied” (optional: ack/hash)

### 11) Semantic validator checklist (beyond schema shape)

Shape validation (JSON schema) is necessary but not sufficient. The compiler
must also enforce semantic invariants:

- `beginRendering` must come after root components for that surface exist.
- Component wrapper contains **exactly one** component key.
- All referenced child IDs must exist.
- Detect and reject cycles in component references.
- Component ID stability:
  - IDs must not change type across updates (e.g. `name_input` cannot switch
    from TextField → Column).
  - ID generation must include enough structure (UI IR path + component type)
    to avoid collisions when templates/repeated fields are introduced.
- Template/dynamic list invariants:
  - template has required fields (binding + componentId)
  - scoped/relative binding paths are interpreted consistently

### 12) Testing strategy: ClientSim + replay tests

Add a minimal “client state machine simulator” (no UI) to regression-test
compiler correctness:

- Apply message streams and assert final per-surface state hash.
- Metamorphic tests:
  - optimizer/coalescing on vs off yields the same final state
- Replay/disconnect tests:
  - partial init (no `beginRendering`) then reconnect and re-init
  - assert deterministic recovery and no “stuck buffering”

Minimum “must-pass” edge cases (P0):

1) beginRendering gate (buffered until beginRendering)
2) root missing (fail fast with a clear error)
3) cycle detection (fail fast)
4) deleteSurface idempotency (double delete is OK)
5) BoundValue `path + literal*` never emitted (compile-time guard)
6) stale userAction rejected (epoch/version check)
7) context DoS rejected (size/depth guard)
8) structured directives enforce `parallel_tool_calls: false` (don’t rely on provider defaults)

### 13) Catalog/capabilities security

Treat catalogs as a security boundary:

- Default to pinned catalog ID (single renderer).
- Default-disable inline catalogs (unless explicitly in dev mode).
- All component types/actions must be allowlisted by the catalog registry.
- If a future client renderer cannot support the pinned catalog/components,
  treat it as a renderer capability error and fall back to a safe path
  (Rails HTML host or plain text), rather than negotiating catalogs in infra.

### 14) Cross-provider LLM constraints (structured outputs)

This compiler plan relies on structured directives being reliable across
providers. Keep these constraints explicit:

- OpenAI-compatible does not mean request-parameter-compatible:
  - Some providers will reject unknown request keys (400/422).
  - Some routers (OpenRouter) may return HTTP 404 (“no endpoints support the requested parameters”)
    when a parameter combination is unsupported.
  - Treat provider/model capability differences as normal. Do not bury them in prompts.
- Add an explicit **request parameter filter/sanitizer** at the LLM boundary (P0 recommendation):
  - Define provider/model capabilities in app config (what request keys are allowed).
  - Before sending a request, drop unsupported keys and record warnings in trace/events.
  - In strict mode (dev/test), raise when a request contains unsupported keys to catch drift early.
  - This should be infra-level (shared by tool calling and directives), but app-owned capabilities.
- Do not combine tool calling with structured outputs in the same LLM request.
- Do not stream LLM responses when using `response_format` or tool calling
  (already enforced in `PromptRunner`).
- Keep structured directives runs tools-free (no `tools`/`tool_choice` alongside
  `response_format`).
- Tool calling runs should default to sequential tool calls
  (`parallel_tool_calls: false`); do not rely on provider defaults.
- Any run that enables `response_format` should explicitly set
  `parallel_tool_calls: false` to avoid provider-default drift (OpenRouter’s
  default is true).

### 15) “Streaming” confusion

A2UI itself is typically streamed (JSONL over SSE/WS).

This is independent from **LLM streaming**.

Our current infra decision is:

- LLM streaming is mutually exclusive with tool calling and `response_format`
  (enforced in `PromptRunner#perform_stream`)
- A2UI streaming is an app transport decision (we can stream compiled messages
  even when the LLM call itself is non-streaming)

### 16) Per-surface atomic emission (avoid half-applied UI)

If we stream A2UI messages and fail mid-stream (guardrail trip, compiler error),
we can leave the client buffering partial updates without `beginRendering`,
which looks like a UI freeze.

P0 rule:

- Compile + validate + size-guard messages **per surface** in memory first.
- Only flush a surface’s message batch once it is complete and valid.

This is compatible with JSONL/SSE (still streamed), but prevents half-initialized
surfaces from being emitted.

### 17) Error codes and trace (contract)

To keep “best-effort production” deterministic and debuggable, define two small
contracts up-front:

1) A stable error code namespace with default recovery actions
2) A trace JSON contract for eval/observability

Error code namespaces (suggested):

- `A2UI_S2C_*`: compile/validate errors on server → client message streams
- `A2UI_C2S_*`: ingress validation errors on client → server events
- `LLM_*`: LLM adapter preflight / protocol incompatibilities

S2C (server → client) recovery mapping (default):

| Code family | Typical issue | Default recovery |
| --- | --- | --- |
| `A2UI_S2C_ENVELOPE_*` | invalid JSONL / not exactly-one-key | **FATAL**: do not flush; safe fallback only |
| `A2UI_S2C_BEGIN_*` | beginRendering gate violated / root missing | **SURFACE_FAIL**: `deleteSurface` then fallback |
| `A2UI_S2C_COMPONENT_*` | missing IDs / wrapper invalid / cycles | **SURFACE_FAIL**: `deleteSurface` then fallback |
| `A2UI_S2C_LIMIT_*` | size/depth/entries guardrail exceeded | **SURFACE_FAIL**: `deleteSurface` then fallback |

C2S (client → server) HTTP mapping (default):

| Code | HTTP | User-facing guidance |
| --- | ---: | --- |
| `A2UI_C2S_ENVELOPE_INVALID` | 400 | “Invalid submission. Please refresh and retry.” |
| `A2UI_C2S_ACTION_FORBIDDEN` | 403 | “This action is not available.” |
| `A2UI_C2S_SURFACE_STALE` | 409 | “UI is out of date. Please regenerate.” |
| `A2UI_C2S_CONTEXT_TOO_LARGE` | 413 | “Submission is too large. Please submit less at once.” |

LLM preflight hard errors (fail fast):

- `LLM_STREAMING_WITH_TOOL_CALLING_FORBIDDEN`
- `LLM_STREAMING_WITH_RESPONSE_FORMAT_FORBIDDEN`
- `LLM_STRUCTURED_OUTPUTS_PARALLEL_TOOL_CALLS_FORBIDDEN`

Trace contract v1 (recommended fields):

- Identity: `trace_version`, `request_id`, `conversation_id`, `turn_index`, timestamps
- Run mode: `mode` (`directives`/`tool_loop`/`hybrid`), `strict_mode`
- LLM config: provider/model, `stream`, `response_format` mode, `parallel_tool_calls`,
  sampling params (temperature/top_p/top_k), routing/provider (OpenRouter)
- Compiler stats (per surface): `surface_id`, epoch/version, optional `surface_rev`,
  message counts, byte counts, component counts, data model entry counts
- Validation: schema/semantic/guardrail status, warnings, error codes
- Recovery: `soft_fail` / `deleteSurface` / `epoch_reset` / fallback reason
- Timing: llm_ms, directives_ms, tool_loop_ms, compile_ms, total_ms

The implementation should centralize codes and default actions in an app-owned
`ErrorRegistry` so infra stays business-agnostic.

## Proposed directive surface (LLM-facing)

Directives should stay high-level. Two viable patterns:

### Pattern A: semantic UI directives (recommended)

Examples:

- `ui.show_form` (open or replace a known form template)
- `ui.toast` (local UI feedback)
- `ui.patch` (patch `/ui_state/...` or `/draft/...`)
- `ui.request_upload`

The compiler decides how these map to surfaces/components/dataModel.

### Pattern B: “A2UI-ish directives”

Examples:

- `ui.surface.open`
- `ui.surface.close`
- `ui.data.replace`
- `ui.data.patch`

This is still high-level (no component trees), but more directly aligned with A2UI.

Implementation detail:

- directive types are injected via `Directives::Registry`
- validator already supports aliases and patch-op normalization:
  `Directives::Validator.validate_patch_ops(...)`

## Development plan (deferred, but ordered)

P0 (foundation):

1) Define a minimal **UI IR** with explicit:
   - surface IDs + epoch/version
   - strong-fact data model namespaces (`/draft`, `/committed`)
   - canonical JSON Pointer paths
2) Define compiler guardrails (size limits, allowlists, action validation).
3) Define failure/recovery policy and make it testable (soft/surface/epoch).
4) Add an LLM boundary request sanitizer (provider capabilities + dropped-key trace)
   so cross-provider parameter drift does not leak into the compiler layer.

P0 DoD (exit criteria):

- UI IR v0 is frozen (documented shape + fixtures) and path canonicalization is
  deterministic (tests).
- Guardrails are implemented and tested (bytes/limits/allowlists/actions).
- Recovery strategies are implemented and testable (soft fail, surface fail,
  epoch reset).
- LLM request parameter filtering is implemented (drop unsupported keys in best-effort,
  raise in strict mode) and is covered by unit tests.
- Trace/error code contracts are implemented at the boundary (enough to replay
  and explain failures in CI artifacts/logs).

P1 (Rails host integration, first UI host):

1) Server-rendered UI builder for Rails (UI IR → HTML, Turbo Frames).
2) Event ingress endpoint:
   - validate `userAction`/`error` envelopes
   - map action → directives/tool loop
3) Use full rebuild/replace updates (Turbo Frame refresh) before attempting diffs.

P1 DoD (exit criteria):

- Rails UI Builder renders UI IR deterministically (tests cover key templates).
- Ingress endpoint validates envelopes + allowlists + nonce + epoch (tests).
- Full rebuild/replace update flow works end-to-end via Turbo Frames.

P2 (A2UI backend, optional renderer target):

1) Add protocol-level infra modules (no app templates):
   - `TavernKit::VibeTavern::A2UI::V0_8::TypedContents`
   - `TavernKit::VibeTavern::A2UI::V0_8::Validator`
   - (optional) `TavernKit::VibeTavern::A2UI::JSONL`
2) Implement an app-owned compiler: UI IR → A2UI message stream (JSON objects).
3) Add deterministic tests for typed contents + validator (CI).

P2 DoD (exit criteria):

- Compiler emits spec-valid v0.8 message streams for a minimal surface
  (validated + size-guarded).
- Per-surface atomic emission is enforced (no partial flush on failure).
- TypedContents/validator have deterministic unit tests (CI).

P3 (ClientSim + eval/hardening):

1) ClientSim state machine for A2UI messages.
2) Replay/disconnect/resume tests.
3) (Optional) Extend eval scripts:
   directives OK → executor → compiler → A2UI validator (compile OK)

P3 DoD (exit criteria):

- ClientSim applies message streams and produces stable per-surface state hashes.
- Metamorphic tests prove optimizer/coalescing does not change semantics.
- Replay/disconnect cases are covered (no “stuck buffering” regressions).

P4 (Renderer integration, optional / later):

1) Decide delivery format:
   - JSON array (debug/dev)
   - JSONL over SSE/WS (production)
2) Choose renderer approach:
   - embed an existing A2UI renderer (Lit/Angular/Flutter), or
   - implement a minimal renderer for the subset of components we use.

P4 DoD (exit criteria):

- Production transport is defined and tested (JSONL over SSE/WS).
- Renderer can display the supported subset and report `error` events for
  recovery testing (epoch reset/deleteSurface).

## Decisions (current)

These are current product preferences (can change later):

- Target UI is a **dedicated UI for a new product**, not a SillyTavern plugin.
- First dedicated UI host is **server-rendered HTML in the Rails app**.
  - We want a dedicated **UI Builder** module/helper that assembles UI from our
    strong-fact UI IR (instead of scattering rendering logic across controllers/views).
  - A future SPA/native client can still consume the compiled UI spec and render it.
- UI IR minimal shape:
  - Start with **forms / prebuilt UI templates** + a small set of generic controls.
  - Keep the UI IR **A2UI-agnostic** (no “A2UI component trees” in the IR).
- UI IR surface routing (P0):
  - Start with a single surface ID: `main`.
  - Keep `assistant_text` as the primary chat transcript; UI surfaces are optional
    companions (side panel / frame), not the only user-visible output.
  - Add additional surfaces only once we have a concrete UI host need (e.g.
    `sidebar`, `wizard:<flow_id>`), and ensure surface IDs are stable (derived
    from UI IR structure, not random).
- First production API uses **Pattern A (semantic UI directives)**.
  We expect some directives to map to **prebuilt, interactive forms** that are
  coupled to product flows (example: uploading a Character Card JSON so an agent
  can read it). This remains app-owned (injected directive registry + templates).
- State store boundary and replay:
  - We likely introduce a conversation-level state store, but allow task/app code
    to be deeply coupled when needed.
  - “Replay” is **best-effort**:
    - UI-level compilation (directives → UI IR → A2UI/HTML) should be deterministic
      given the same inputs.
    - App-coupled side effects may not be reproducible purely from chat logs.
  - Prefer storing user submissions + state snapshots to support recovery/debugging.
- v0.8 `dataModelUpdate.contents` **array strategy**: keep the A2UI data model
  array-free initially and let the UI control + submission handler normalize to
  JSON arrays in domain state. Two preferred UX approaches:
  - tags-style input control, normalized to JSON array on submit
  - comma-separated input with UX guardrails, normalized to JSON array on submit
- Default values: do not rely on client-side implicit data model writes.
  - Compiler must not emit BoundValue `path + literal*` shorthands.
  - Defaults are applied via explicit `dataModelUpdate`.
- Path canonicalization:
  - UI IR uses JSON Pointer paths (leading `/`) consistently.
  - Compiler accepts and canonicalizes segment paths at the boundary.
  - Non-`/` paths are treated as relative to the draft namespace (e.g. `/draft/`)
    and should emit warnings in logs/trace.
- Action allowlist (v0):
  - Use an app-owned allowlist registry for actions (names + context schema).
  - The compiler only emits allowlisted actions, and the server rejects any
    non-allowlisted action on ingress.
  - Model this similar to tool calling “masking”: hide/disable actions that are
    not valid for the current flow.
- Catalog negotiation: start **pinned** to a single app-selected catalog.
  Negotiation via client-reported `supportedCatalogIds` only matters once we
  have multiple client renderers. This belongs to the app layer (config/injected
  registries), not the infra.
- Catalog versioning:
  - Do not implement catalog version negotiation initially.
  - Prefer app-owned UI snapshots for “completed” UIs:
    - lock editing/interaction when a snapshot is no longer compatible
    - render an “expired UI” stub with a safe explanation
    - provide “regenerate” as the primary self-recovery UX
- Compiler strictness in production: **best-effort**.
  - Never emit invalid A2UI messages.
  - If compilation/validation fails for a surface, drop that surface’s messages
    and fall back to safe output (e.g., plain `assistant_text` that explicitly
    says the UI could not be rendered and offers “regenerate”).
  - If failure risks leaving stale UI behind, prefer `deleteSurface` or epoch
    reset over silent drops.
  - Use strict mode in dev/test to catch template/compiler bugs early.
- A2UI protocol mode:
  - Default to **strict** (spec-compliant).
  - Add an explicit **extended** mode only when we intentionally diverge from
  A2UI to support our own renderer needs (and keep it opt-in + versioned).
- IDs and epochs:
  - IDs are stably derived from UI IR.
  - Epoch/version only changes on recovery/reset; it is not a normal update mechanism.
- Rails UI Builder API:
  - Start simple: render **UI IR → HTML directly** (via a dedicated builder/helper).
  - If/when complexity grows, introduce an intermediate view model (UI IR → VM → HTML).
- Rails host incremental updates:
  - Use **Turbo Frames/Streams**.
- Update strategy (initial):
  - Prefer **full rebuild/replace** of a surface (Turbo Frame refresh, or A2UI
    re-init) over incremental diffs.
  - Add optimizations only after ClientSim tests prove semantic equivalence.
- Turbo mapping (initial):
  - one surface = one Turbo Frame
- Modals (initial):
  - Do not support a “modal surface” initially.
  - Prefer inline UI flows (normal surfaces / frames).
  - If a modal UX is needed, trigger it from normal UI (e.g., a button) and
    implement it at the Rails UI layer (Turbo/Stimulus), not as a new protocol layer.
- UI Builder determinism/testing:
  - Keep the builder input-only (no hidden state, no DB reads, no time/randomness).
  - Stable ordering for lists; stable IDs derived from UI IR.
  - Prefer structural assertions in tests (parse HTML / selector-based), and only
    use string snapshots if we can normalize output reliably.
- `userAction` idempotency keys (recommended):
  - Require an idempotency key (event ID) for client → server submissions.
  - Server should deduplicate within a bounded TTL (per conversation/surface).
  - This prevents double-submit bugs and makes retries/disconnect replays safer.
- A2UI renderer ACK/hash mechanism:
  - Do **not** implement ACK/hash in the first production iteration.
  - Rely on:
    - client-reported `error` events, and
    - a manual “regenerate” UX for self-recovery
  - Future extension (optional):
    - client can report an “applied surface hash” (or epoch/version) so the
      server can detect “updates not applied” and trigger epoch reset.
    - keep it opt-in and versioned, since not all renderers will support it.

## Open questions (remaining)

- When (if ever) do we introduce modal-specific patterns beyond the Rails UI layer?
  - If we do, do we model it as a separate Turbo Frame, or as a UI state flag that
    changes CSS/behavior for an existing frame?
