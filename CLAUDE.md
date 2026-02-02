# Vibe Tavern (Rails) - AI Dev Guardrails

This repo rewrites the legacy TavernKit codebase, available locally at
`resources/tavern_kit` (symlink, not committed).

- Rails app rewrite source: `resources/tavern_kit/playground`
- Embedded gem rewrite source: `resources/tavern_kit`
- Upstream repo: `https://github.com/jasl/tavern_kit`
Primary goal: reduce "vibe coding" churn by enforcing consistent boundaries,
small diffs, and test-driven feedback.

## Stack (Assumptions)

- Rails: 8.2 (edge)
- Ruby: see `.ruby-version`
- DB: PostgreSQL 17+ with pgvector extension
- Frontend: Hotwire (Turbo + Stimulus)
- Assets: Propshaft + jsbundling/cssbundling (Bun)
- CSS: Tailwind (via bun scripts)
- Background: Solid Queue / Solid Cache / Solid Cable
- Tests: Minitest + fixtures (no RSpec)
- Style: `rubocop-rails-omakase`

## Development Environment Setup

### Prerequisites

- Ruby (see `.ruby-version`)
- Bun (for JavaScript/CSS bundling)
- PostgreSQL 17+ with pgvector extension

### Database Setup

The app requires PostgreSQL with pgvector. Check if local PostgreSQL is available:

```sh
pg_isready
```

**Option A: Local PostgreSQL available**

If you have PostgreSQL running locally with pgvector, no extra setup needed.
The app will connect via Unix socket by default.

**Option B: Use Docker (recommended for environments without pgvector)**

Start PostgreSQL with pgvector using the provided compose file:

```sh
docker compose -f compose.dev.yaml up -d
```

Then create `.env` file (or copy from template):

```sh
cp env.sample .env
# Edit .env and set:
# RAILS_DB_URL_BASE=postgresql://postgres:postgres@localhost:5432
```

Verify the container is running:

```sh
docker compose -f compose.dev.yaml ps
```

To stop the database:

```sh
docker compose -f compose.dev.yaml down
```

### Initial Setup

After database is ready:

```sh
bin/setup
```

This will:
- Install Ruby dependencies (bundle)
- Install JavaScript dependencies (bun)
- Generate credentials (if not exist)
- Prepare databases (create + migrate)

### Running the App

```sh
bin/dev
```

The server binds to `0.0.0.0:3000` for remote access.

## Golden Paths (Commands)

Prefer these repo-specific entrypoints to avoid drift:

- Setup (idempotent): `bin/setup`
- Run dev (web + Procfile.dev): `bin/dev`
- Full local CI (fastest "is this ready" check): `bin/ci`

Tests:

- Full suite: `bin/rails test`
- Single directory: `bin/rails test test/services/`
- Single file: `bin/rails test test/models/user_test.rb`
- Single test (by line): `bin/rails test test/models/user_test.rb:42`
- System tests (optional): `bin/rails test:system`

Rails debugging:

- Console: `bin/rails console`
- Routes: `bin/rails routes`

Quality/Security:

- Ruby style: `bin/rubocop` (auto-correct: `bin/rubocop -A`)
- Dependency audit: `bin/bundler-audit`
- Security scan: `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`
- Autoload sanity: `bin/rails zeitwerk:check`

Database:

- Prepare (create/migrate as needed): `bin/rails db:prepare`
- Migrate: `bin/rails db:migrate`
- Rollback: `bin/rails db:rollback`
- Status: `bin/rails db:migrate:status`
- Reset (when you truly need a clean slate): `bin/rails db:reset`
- Seeds (reset + re-seed): `bin/rails db:seed:replant`
- Multi-DB note: this app has separate DBs for primary/queue/cable. In normal
  development, do not manually manage Solid* migrations; only revisit
  `db/*_migrate` during dependency upgrades (handled manually).

Background jobs:

- Run worker: `bin/jobs`

JavaScript/CSS:

- Package manager: Bun (avoid npm/yarn)
- Lint: `bun run lint`
- Auto-fix lint: `bun run lint:fix`
- Build (one-shot): `bun run build` and `bun run build:css`
- `bin/setup` uses `bun install --frozen-lockfile` (keep `bun.lock` in sync)

Embedded gem (TavernKit):

- Path: `vendor/tavern_kit/` (standalone Ruby gem, not a Rails app)
- Setup deps: `vendor/tavern_kit/bin/setup`
- Run gem tests + lint: run from `vendor/tavern_kit/` -> `bundle exec rake`
- Run gem tests only: run from `vendor/tavern_kit/` -> `bundle exec rake test`
- Run gem rubocop: run from `vendor/tavern_kit/` -> `bundle exec rubocop`
- Console: run from `vendor/tavern_kit/` -> `bin/console`
- Dev note: Rails usually won't reload gem code; restart `bin/dev` after changing
  files under `vendor/tavern_kit/`.

When changing code under `vendor/tavern_kit/`, run both:

- Gem suite: `bundle exec rake` (in `vendor/tavern_kit/`)
- App suite (integration): `bin/rails test`

Generators:

- Rails generators should produce Minitest tests.
- Helpers/assets generation is disabled (create manually when needed).

## Architecture Mode: DHH Baseline + Selective Modern Layers

Default philosophy is 37signals/DHH (rich domain models, concerns, CRUD routing).
We *also* allow service/query/presenter as tools to control complexity.
Treat these as a toolbox, not a mandatory layering scheme.

### Decision Rules (Use The Smallest Tool That Fits)

Use this decision tree in order:

1) **Model / Concern (default)**
   - Put: invariants, state transitions, domain behavior, validations, associations.
   - OK: small side effects strictly tied to persistence (e.g., normalization).
   - Avoid: orchestration across multiple aggregates, external I/O.

2) **Query object (complex reads)**
   - Use when: listing/search/filtering needs joins, preloads, pagination,
     composable filters, or performance tuning.
   - Contract: returns an `ActiveRecord::Relation` (or plain result), no writes,
     no external calls.
   - Inputs: pass context explicitly (e.g., `current_user`, `current_account`).
     Avoid reaching into `Current` inside queries.

3) **Service object (complex writes / workflows)**
   - Use when: multi-step workflow, multi-model transaction, background job
     enqueueing, emails/webhooks, or anything with meaningful orchestration.
   - Contract: call explicit model methods for domain transitions; keep services
      thin and deterministic (prefer idempotent entrypoints).
   - Inputs: pass context explicitly (e.g., `current_user`, `current_account`).
     Avoid reaching into `Current` inside services.
   - Return: prefer a `Result` (see `app/services/result.rb`) with `success?`,
     `value`, `errors`, and optional `code`. Use `Result.failure(...)` for
     expected failures; raise for truly exceptional failures.

4) **Presenter (view-facing formatting/composition)**
   - Use when: templates start accumulating formatting and branching.
   - Contract: no DB writes; avoid heavy queries (pass preloaded records in).

### Practical Heuristics

- If it changes *one* aggregate, start in the model.
- If it reads *many* records in a complicated way, use a query.
- If it writes *many* records or talks to the outside world, use a service.
- If it only changes how data is displayed, use a presenter.

## File/Directory Conventions

Keep the project predictable. Prefer these locations:

- `app/models/` and `app/models/concerns/`
- `app/controllers/` and `app/controllers/concerns/`
- `app/queries/` (query objects)
- `app/services/` (workflow/application services)
- `app/presenters/` (view-facing presenters)

Naming conventions:

- Queries: `SomethingQuery` with a single public method (`#call` or `#relation`).
- Services: verb-ish, explicit entrypoints (`CreateX`, `CloseY`, `SyncZ`).
- Presenters: `SomethingPresenter`.

## Testing Rules (Minitest)

Keep tests fast and deterministic.

- Use fixtures by default (`test/fixtures/*.yml`).
- Prefer unit tests over system tests unless behavior requires full stack.
- New code should usually ship with tests.

Suggested test placement:

- Models: `test/models/**/*_test.rb`
- Queries: `test/queries/**/*_test.rb`
- Services: `test/services/**/*_test.rb`
- Presenters: `test/presenters/**/*_test.rb`
- System: `test/system/**/*_test.rb`

## Rewrite Guardrails (Playground -> Vibe Tavern)

- Preserve behavior first. Avoid opportunistic refactors during porting.
- Port in vertical slices (a feature end-to-end), keeping diffs small.
- When uncertain, consult the reference implementation under
  `resources/tavern_kit/playground` and add characterization tests.

## Anti-Hallucination Rules (How To Work In This Repo)

- Read existing code before editing; do not guess file locations or patterns.
- Search first (grep) for similar code and follow the local convention.
- Prefer small, reviewable changes; avoid mixing refactors with behavior changes.
- Run the narrowest relevant test command locally before claiming "done".
- Do not introduce new gems/tools without a concrete need and a repo-wide fit.
