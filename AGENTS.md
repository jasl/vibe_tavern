# AGENTS.md

This file is a tool-agnostic guide for AI coding agents ("vibe coding" tools)
working in this repository.

## Source Of Truth

- Project constraints and guardrails: `CLAUDE.md`
- Optional, project-local agent prompts: `.claude/`

If this file conflicts with `CLAUDE.md`, follow `CLAUDE.md`.

## Project Context

- Repo: Vibe Tavern (Rails)
- Rewrite target: `/Users/jasl/Workspaces/tavern_kit/playground`
- Goal: reduce churn and hallucinations via strict boundaries, small diffs, and
  test-driven feedback.

## Stack Notes

- Rails: 8.2 (edge)
- Ruby: see `.ruby-version`
- DB: Postgres (multi-DB: primary/queue/cable)
- Frontend: Hotwire (Turbo + Stimulus)
- Assets: Propshaft + jsbundling/cssbundling (Bun)
- Tests: Minitest + fixtures

## Architecture: DHH Baseline + Selective Modern Layers

Default philosophy is 37signals/DHH (rich models, concerns, CRUD routing).
We also allow service/query/presenter as *tools* to control complexity.

Use the smallest tool that fits:

1. Model / Concern (default)
2. Query object (complex reads)
3. Service object (complex writes/workflows)
4. Presenter (view-facing formatting/composition)

See `CLAUDE.md` for the detailed decision rules.

Service objects should return a consistent `Result` (see `app/services/result.rb`).

## Directory Conventions

- Models: `app/models/` and `app/models/concerns/`
- Controllers: `app/controllers/` and `app/controllers/concerns/`
- Queries: `app/queries/`
- Services: `app/services/`
- Presenters: `app/presenters/`

Tests (Minitest):

- Models: `test/models/**/*_test.rb`
- Queries: `test/queries/**/*_test.rb`
- Services: `test/services/**/*_test.rb`
- Presenters: `test/presenters/**/*_test.rb`
- System: `test/system/**/*_test.rb`

## Workflow Requirements (Anti-Hallucination)

- Read before edit: do not guess file locations or patterns.
- Search first: use code search to find similar implementations.
- Keep diffs small: avoid mixing refactors with behavior changes.
- Preserve behavior first: when porting, prefer characterization tests.
- No new dependencies without a concrete need and repo-wide fit.

## Testing And Verification

- Prefer the narrowest relevant test command:
  - `bin/rails test test/models/...`
  - `bin/rails test test/services/...`
  - `bin/rails test test/queries/...`

If security/lint tools are relevant:

- `bin/rubocop`
- `bin/brakeman`
- `bin/bundler-audit`

## Golden Commands

These reduce ambiguity across tools/machines:

- Setup (idempotent): `bin/setup`
- Run dev: `bin/dev`
- Full local CI: `bin/ci`

Tests:

- Full suite: `bin/rails test`
- Single file: `bin/rails test test/models/user_test.rb`
- Single test (by line): `bin/rails test test/models/user_test.rb:42`

Rails debugging:

- Console: `bin/rails console`
- Routes: `bin/rails routes`

Quality/Security:

- Ruby style: `bin/rubocop` (auto-correct: `bin/rubocop -A`)
- Dependency audit: `bin/bundler-audit`
- Security scan: `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`
- Autoload sanity: `bin/rails zeitwerk:check`

Database:

- Prepare: `bin/rails db:prepare`
- Migrate: `bin/rails db:migrate`
- Rollback: `bin/rails db:rollback`
- Status: `bin/rails db:migrate:status`
- Reset (preferred over ad-hoc drop/create): `bin/rails db:reset`
- Seeds: `bin/rails db:seed:replant`
- Multi-DB note: this app uses separate DBs for primary/queue/cable. Avoid
  touching `db/*_migrate` unless you are explicitly performing a dependency
  upgrade.

Background jobs:

- Run worker: `bin/jobs`

JavaScript/CSS:

- Package manager: Bun (avoid npm/yarn)
- Lint: `bun run lint`
- Auto-fix lint: `bun run lint:fix`
- Build (one-shot): `bun run build` and `bun run build:css`
- `bin/setup` uses `bun install --frozen-lockfile` (keep `bun.lock` in sync)

Embedded gem (TavernKit):

- Path: `lib/tavern_kit/` (standalone Ruby gem)
- Setup: `lib/tavern_kit/bin/setup`
- Tests + lint: run from `lib/tavern_kit/` -> `bundle exec rake`
- Dev note: Rails usually won't reload gem code; restart `bin/dev` after changing
  files under `lib/tavern_kit/`.

## Project-Local Agent Prompts (.claude)

This repo keeps some agent prompts local to avoid polluting `~/.claude`.

Agents:

- `.claude/agents/vt-model.md`: rich models + concerns (DHH baseline)
- `.claude/agents/vt-query.md`: query objects for complex reads
- `.claude/agents/vt-service.md`: service objects for complex workflows
- `.claude/agents/vt-presenter.md`: presenters for view-facing formatting

Skills:

- `.claude/skills/vibe-tavern-guardrails.md`: condensed project guardrails
- `.claude/skills/rails-tdd-minitest.md`: TDD workflow for Rails using Minitest
- `.claude/skills/rails-security-review.md`: Rails security checklist + scans
- `.claude/skills/rails-database-migrations.md`: safe Postgres migrations

If your tool does not support auto-loading `.claude/`, treat these files as
reference prompts to follow manually.
