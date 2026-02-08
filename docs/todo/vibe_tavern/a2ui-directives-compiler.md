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
  - arrays are not first-class in `contents` in v0.8, so list-like UI needs an
    explicit strategy (see “Edge cases”)

All of these rules are described in the A2UI repo:

- `resources/A2UI/docs/reference/messages.md`
- `resources/A2UI/specification/v0_8/docs/a2ui_protocol.md`
- `resources/A2UI/specification/v0_8/json/server_to_client.json`

## Hard problems / risks (and how to de-risk them)

### 1) Safety: “data not code” is necessary but not sufficient

Even as pure data, A2UI can DoS a client if we allow unbounded output.

Guardrails to implement in the compiler (and validate again at the boundary):

- max messages per response
- max bytes per message / per surface / per response
- max component count per surface
- max data model depth / entry count / string bytes
- strict allowlist of component types (catalog-driven)
- strict allowlist of allowed actions (button/event names) and context keys

### 2) Version drift (A2UI evolves)

The A2UI repo includes v0.8 (stable) and newer draft specs (v0.9+).

Compiler approach reduces risk:

- the LLM never sees the A2UI version or exact shape
- version upgrades are internal: swap compiler target + renderer

Decision (recommended):

- Pin to A2UI v0.8 first (stable), and only add v0.9+ once we have a concrete
  renderer and a migration reason.

### 3) Data model arrays (v0.8 typed adjacency list)

`dataModelUpdate.contents` supports strings/numbers/booleans/maps, not arrays.

Strategies (choose one explicitly; don’t let this drift):

- **No arrays (initial)**: represent lists as fixed UI components (explicit children)
- **Encode arrays as maps**: keys `"0"`, `"1"`, ... and define renderer semantics
- **Custom catalog component**: e.g. `Repeater` that expects a map-like structure

### 4) Event handling / round-trips

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

### 5) “Streaming” confusion

A2UI itself is typically streamed (JSONL over SSE/WS).

This is independent from **LLM streaming**.

Our current infra decision is:

- LLM streaming is mutually exclusive with tool calling and `response_format`
  (enforced in `PromptRunner#perform_stream`)
- A2UI streaming is an app transport decision (we can stream compiled messages
  even when the LLM call itself is non-streaming)

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

## Development plan (deferred)

## Decisions (current)

These are current product preferences (can change later):

- Target UI is a **dedicated UI for a new product**, not a SillyTavern plugin.
- First dedicated UI host is **server-rendered HTML in the Rails app**.
  - We want a dedicated **UI Builder** module/helper that assembles UI from our
    strong-fact UI IR (instead of scattering rendering logic across controllers/views).
  - A future SPA/native client can still consume the compiled UI spec and render it.
- First production API uses **Pattern A (semantic UI directives)**.
  We expect some directives to map to **prebuilt, interactive forms** that are
  coupled to product flows (example: uploading a Character Card JSON so an agent
  can read it). This remains app-owned (injected directive registry + templates).
- v0.8 `dataModelUpdate.contents` **array strategy**: keep the A2UI data model
  array-free initially and let the UI control + submission handler normalize to
  JSON arrays in domain state. Two preferred UX approaches:
  - tags-style input control, normalized to JSON array on submit
  - comma-separated input with UX guardrails, normalized to JSON array on submit
- Catalog negotiation: start **pinned** to a single app-selected catalog.
  Negotiation via client-reported `supportedCatalogIds` only matters once we
  have multiple client renderers. This belongs to the app layer (config/injected
  registries), not the infra.
- Compiler strictness in production: **best-effort**.
  - Never emit invalid A2UI messages.
  - If compilation/validation fails for a surface, drop that surface’s messages
    and fall back to safe output (e.g., plain `assistant_text`, or a minimal
    error UI that cannot mislead).
  - Use strict mode in dev/test to catch template/compiler bugs early.
- A2UI protocol mode:
  - Default to **strict** (spec-compliant).
  - Add an explicit **extended** mode only when we intentionally diverge from
    A2UI to support our own renderer needs (and keep it opt-in + versioned).

### Phase 1 — Ruby infra: A2UI v0.8 primitives (no UI templates yet)

Add protocol-level modules (still infra, not product-specific):

- `TavernKit::VibeTavern::A2UI::V0_8::TypedContents`
  - Ruby Hash → typed adjacency list (`dataModelUpdate.contents`)
  - hard limits: depth, entry count, string bytes
  - explicit strategy for arrays and nils
- `TavernKit::VibeTavern::A2UI::V0_8::Validator`
  - validates envelope shape, one-of message keys, ordering, typed contents shape
  - returns structured errors with JSON pointer-ish paths (for logs/eval)
- (optional) `TavernKit::VibeTavern::A2UI::JSONL`
  - messages array → JSONL (one object per line)

Deterministic tests (Minitest):

- typed contents: depth/entry/string limits, array strategy, nil strategy
- validator: one-of keys, beginRendering ordering, wrapper “one key only”

### Phase 2 — App layer: UI IR + compiler + a minimal template

App-owned code (NOT infra):

- `UiIR` (strong-fact UI state)
  - surfaces, active surface, per-surface data model
- directive executor (update `UiIR` deterministically)
- compiler: `UiIR` → A2UI messages
  - stable component IDs
  - stable surface ID strategy
  - message grouping per surface

Start with one template:

- “character form” or “upload request”

### Phase 3 — Transport + renderer integration

Decide delivery format:

- JSON array (debug/dev) then JSONL over SSE (production)

Renderer:

- either embed an existing A2UI renderer (Lit/Angular/Flutter), or
- implement a minimal renderer for the subset of components we use

### Phase 4 — Evaluation + hardening

Extend existing eval scripts (optional):

- directives eval: after directives success, run:
  executor → compiler → A2UI validator
  and report:
  - “directives OK”
  - “A2UI compile OK”
  - message counts / bytes / per-surface component counts

This keeps LLM evaluation focused on directives (not on producing A2UI).

## Open questions (remaining)

- What should the Rails **UI Builder** public API look like (inputs/outputs)?
  - Should it render UI IR → HTML directly, or UI IR → “view model” → HTML?
  - How do we keep rendering deterministic and testable (no hidden state)?
- For the Rails host, how do we deliver incremental updates?
  - full-page reload vs Turbo Frames/Streams vs JSON endpoint + client hydration
