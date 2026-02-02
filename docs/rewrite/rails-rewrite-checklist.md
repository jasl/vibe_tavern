# Rails Rewrite Integration Checklist (No UI)

This is an implementation checklist for integrating TavernKit into the Rails
rewrite. It is intentionally **business-logic only**: models, services, jobs,
and tests. Any UI/admin screens are out of scope and can be added later.

Source of truth for integration semantics:
- `docs/rewrite/rails-integration-guide.md`

## Non-goals (this checklist)

- No UI (no views/components); at most, internal services + optional API endpoints.
- No provider networking inside TavernKit (the app owns provider clients).
- No persistence inside TavernKit (the app owns DB).

## Core Concepts to Implement in Rails

- **Content models**: Character / Lore / Preset / Template / MessageHistory.
- **Session state**: `variables_store` (persisted, per chat).
- **Per-build snapshot**: `runtime` (not persisted; derived per request/build).
- **Prompt build**: inputs -> `Prompt::Plan` -> dialect messages.
- **Observability**: store/replay-friendly artifacts (`fingerprint`, `trace`, `trim_report`).

---

## Milestone 0: Skeleton + Conventions

Deliverable:
- Rails app can run and tests can execute without any TavernKit integration.

Tasks:
- Create `PromptBuilding::*` namespace for services.
- Add shared helpers for JSON columns and validation patterns (use plain Ruby).

Tests:
- Smoke test: `bin/rails test` stays green.

---

## Milestone 1: Domain Models (Persistence Only)

Deliverable:
- Rails persists all prompt-building inputs/outputs required to build a plan.

Migrations (suggested tables; adjust naming as desired):
- `characters`:
  - `data` (jsonb) - CCv2/CCv3 hash
  - optional: `spec`/`spec_version` (derived), `name` (cached), `tags` (cached)
  - ActiveStorage attachment: `main_image`
- `lore_books`:
  - `data` (jsonb) - ST World Info hash or CC character_book hash
  - optional: `name`, `format` enum (:silly_tavern_world_info / :character_book / :risu_lorebook)
- `presets`:
  - `data` (jsonb) - ST preset hash, or RisuAI preset hash (includes `promptTemplate`)
  - optional: `name`, `dialect_default`
- `prompt_templates` (optional; RisuAI):
  - Only if you want to store templates separately and reuse them across chats/presets.
  - The TavernKit pipeline expects `preset` to include `promptTemplate`, so if you persist
    templates separately, merge them into the preset hash at build-time.
- `chats`:
  - `character_id`, `preset_id` or `prompt_template_id` (depending on mode)
  - `variables_store` (jsonb) - session-level mutable store (persisted)
  - optional: `mode` enum (:silly_tavern / :risuai)
- `messages`:
  - `chat_id`, `role`, `content`, `name`, `metadata` (jsonb), `position` (int)

Models:
- `Character`, `LoreBook`, `Preset`, `PromptTemplate`, `Chat`, `Message`
- Minimal validations:
  - JSON columns must be objects/arrays of expected shape (shallow validate; deep validate via TavernKit services below).
  - Prevent cross-chat sharing of `variables_store`.

Tests:
- Model validation tests for required columns + basic shape.

---

## Milestone 2: Import/Upload Services (Ingest + Persistence)

Deliverable:
- Rails can import supported file formats into persisted domain models.

Services (examples):
- `Importing::ImportCharacterFromUpload.call(upload_io_or_path)`
  - Use `TavernKit::Ingest.open(path)` (PNG/BYAF/CHARX) or `JSON.parse` (raw)
  - Persist:
    - `Character.data` = normalized CC hash (`bundle.character.to_h` or exporter output)
    - attach `bundle.main_image_path` (if present) to ActiveStorage
  - Record and surface `bundle.warnings` (log + store in import record if desired)
  - For `bundle.assets` (zip assets): decide policy:
    - store metadata only and lazy-read later, or
    - eagerly import a subset (bounded reads), or
    - ignore everything except main image

Optional endpoints (still no UI):
- `POST /imports/characters` that accepts upload and returns `{character_id, warnings}`.

Tests:
- Service tests with fixture files (hand-authored in app):
  - PNG with chara/ccv3 precedence
  - BYAF with multiple characters (warn; import first)
  - CHARX with embedded assets (ensure tmp cleanup)

---

## Milestone 3: VariablesStore + Runtime Assembly (App ↔ Pipeline Sync)

Deliverable:
- Rails can reliably create `variables_store` and `runtime` for every prompt build.

Services:
- `PromptBuilding::LoadVariablesStore.call(chat)`:
  - Load JSONB -> `TavernKit::VariablesStore::InMemory`
  - Enforce scopes and serialization rules (string keys at boundary OK; store normalizes internally)
- `PromptBuilding::BuildRuntime.call(chat, request_context:)`:
  - Build `TavernKit::Runtime::Base.build({ ... }, type: :app, id: chat.id)`
  - Compute/derive:
    - `chat_index`, `message_index` (from DB message count / request)
    - RisuAI: `cbs_conditions`, `toggles`, `metadata`, `modules`, `assets` as needed
  - Do not persist runtime; treat it as a per-build snapshot.

Concurrency policy (important):
- When building prompts concurrently for the same chat, guard `variables_store` writes:
  - Option A (simple): row lock (`chat.with_lock`) during build+persist store.
  - Option B: optimistic lock on `chats.lock_version`.
  - Pick one and lock it down with tests.

Tests:
- variables_store round-trip tests
- runtime defaults tests (tolerant mode)
- concurrency safety test for store update (use lock/optimistic strategy)

---

## Milestone 4: Prompt Build Service (ST + RisuAI)

Deliverable:
- Rails can build a prompt plan/messages deterministically for both modes.

Note:
- If the rewrite chooses an app-owned pipeline (not ST/RisuAI), swap the build call to:
  - `TavernKit::VibeTavern.build { ... }`, or
  - `TavernKit.build(pipeline: PromptBuilding::Pipeline) { ... }`
  (and keep the rest of the service contract the same).

Service (single entrypoint):
- `PromptBuilding::BuildPlan.call(chat:, user_input:, dialect: :openai, strict: Rails.env.test?)`
  - Load persisted content:
    - Character, Preset/LoreBooks, TemplateCards, Message history
  - Construct:
    - `variables_store` via service
    - `runtime` via service
    - `instrumenter` in development (`TraceCollector`) else nil
  - Call TavernKit:
    - ST: `TavernKit::SillyTavern.build { ... }`
    - RisuAI: `TavernKit::RisuAI.build { ... }`
  - Return `Prompt::Plan`
  - Persist `variables_store` back to chat after build (if mutated)

Tests:
- Integration tests (Rails-level) that assert:
  - plan builds with no warnings in strict mode for known-good inputs
  - plan messages shape matches dialect requirements
  - `variables_store` mutation persists when triggers/macros write vars

---

## Milestone 5: Provider Request Layer (No UI)

Deliverable:
- Rails can turn Plan -> provider request payload and persist the turn.

Services:
- `LLM::BuildRequest.call(plan:, provider:, model:, options:)`
  - `plan.to_messages(dialect: ...)` + provider-specific top-level fields
  - Use `plan.fingerprint(...)` for caching/replay keys
- `LLM::SendRequest.call(request_payload)` (HTTP client; app-owned)
- `Chats::AppendAssistantMessage.call(chat:, provider_response:)`

Tests:
- Request builder tests (pure Ruby)
- End-to-end test with a fake provider client

---

## Milestone 6: Observability / Debugging Artifacts

Deliverable:
- Rails can reproduce “why this prompt” decisions for failures and regressions.

Add (optional, but strongly recommended for RP/Agent apps):
- `prompt_builds` table (or append-only events):
  - `chat_id`, `fingerprint`, `dialect`, `model`, `payload_summary` (jsonb)
  - `warnings` (jsonb), `trim_report` (jsonb), `trace` (jsonb), `duration_ms`
- Logging policy:
  - development: store trace + debug_dump (bounded)
  - production: store fingerprint + warnings + trim_report; trace only on demand

Tests:
- TraceCollector integration test (only in development config)
- Fingerprint stability test for identical inputs

---

## Milestone 7: Regression Gate Suite (Keep it From Drifting)

Deliverable:
- Rails has a “stop the line” gate similar to the gem’s contract/conformance guardrails.

Add a small, stable Rails integration suite:
- ST:
  - continue+continue_prefill displacement case
  - doChatInject ordering case
  - group activation strategy case
- RisuAI:
  - CBS deterministic RNG case
  - triggers “prompt-building-safe” effects case

Tests:
- Put under `test/integration/prompt_building/**/*_test.rb`
- Run on CI via `bin/ci` (already in place)
