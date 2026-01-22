# AGENTS.md

This file is a tool-agnostic guide for agentic coding tools working in this
repository. It prioritizes reproducible commands and repo-specific conventions.

## Source Of Truth

- Constraints + architecture rules: `CLAUDE.md`
- Project-local agent prompts/skills: `.claude/`

If this file conflicts with `CLAUDE.md`, follow `CLAUDE.md`.

## Repo Context

- Repo: Vibe Tavern (Rails)
- Legacy reference sources (local symlink, ignored): `resources/tavern_kit`
- Rails rewrite reference: `resources/tavern_kit/playground`
- Embedded gem source: `lib/tavern_kit/`

## Golden Commands

Use these entrypoints (they encode local assumptions):

```sh
bin/setup                   # deps + credentials + db:prepare (idempotent)
bin/dev                     # dev Procfile + rails server
bin/ci                      # local CI: lint + security + tests (see config/ci.rb)
```

Build / lint / security:

```sh
bin/rubocop                 # ruby lint (fix: bin/rubocop -A)
bun run lint                # eslint (fix: bun run lint:fix)
ruby bin/lint-eof           # enforce exactly one newline at EOF (fix: --fix)

bin/bundler-audit           # gem CVE audit (config: config/bundler-audit.yml)
bin/brakeman --no-pager     # rails static security scan
bin/rails zeitwerk:check    # autoload sanity
```

Tests (Minitest):

```sh
bin/rails test                           # full suite
bin/rails test test/models/              # directory
bin/rails test test/models/user_test.rb  # single file
bin/rails test test/models/user_test.rb:42  # single test by line
bin/rails test:system                    # system tests
```

Frontend assets (Bun + Tailwind):

```sh
bun run build            # js build (bun.config.js)
bun run build:css        # tailwind build
bun run build --watch    # used by Procfile.dev
bun run build:css --watch
```

Embedded gem (TavernKit):

```sh
cd lib/tavern_kit && bin/setup
cd lib/tavern_kit && bundle exec rake        # gem tests + lint
cd lib/tavern_kit && bundle exec rake test   # gem tests only
```

## Formatting And Style

Editor baseline: `.editorconfig`

- Indentation: 2 spaces; LF line endings; final newline required; 150 char line limit
- Extra blank lines at EOF are rejected; use `ruby bin/lint-eof`

Ruby style: `.rubocop.yml` (inherits `rubocop-rails-omakase`)

- Strings: prefer double quotes
- Multiline literals: trailing commas (`diff_comma`) for arrays/hashes
- Avoid whitespace inside `[]` literals
- Imports: prefer Rails autoloading (constants) over `require` for app code

JavaScript style: `eslint.config.js`

- ESM modules (`import ... from ...`)
- Prefer `const`/`let`; forbid `var`
- Unused vars: allowed only when prefixed with `_`
- `console.*` is allowed but warned (keep it out of committed code when possible)
- Types: this repo uses plain JS in `app/javascript/` (no TypeScript config)

## Architecture + Naming

Default philosophy: DHH baseline (rich models, CRUD routing). Use extra layers only to control complexity.

Use the smallest tool that fits:

1. Model / Concern (default)
2. Query object (complex reads)
3. Service object (complex writes/workflows)
4. Presenter (view composition/formatting)

Directory conventions:

- Models: `app/models/`, concerns: `app/models/concerns/`
- Controllers: `app/controllers/`, concerns: `app/controllers/concerns/`
- Queries: `app/queries/`
- Services: `app/services/`
- Presenters: `app/presenters/`

Naming conventions:

- Queries: `SomethingQuery` with one public entrypoint (`#call` or `#relation`)
- Services: verb-ish entrypoints (`CreateX`, `CloseY`, `SyncZ`)
- Presenters: `SomethingPresenter`

## Error Handling

Services should return a `Result` (see `app/services/result.rb`) for expected
failures.

- Expected failures: `Result.failure(errors: ..., code: ...)`
- Success path: `Result.success(value: ..., code: ...)`
- Exceptions: raise only for truly exceptional/unexpected failures
- Never swallow errors: avoid empty `rescue` blocks
- Prefer passing `ActiveModel::Errors` into `Result.failure(errors: ...)` (it normalizes via `full_messages`)

## Testing Conventions

Test stack: Minitest + fixtures (no RSpec).

Where tests go:

- Models: `test/models/**/*_test.rb`
- Controllers: `test/controllers/**/*_test.rb`
- Integration/requests: `test/integration/**/*_test.rb`
- Queries: `test/queries/**/*_test.rb`
- Services: `test/services/**/*_test.rb`
- Presenters: `test/presenters/**/*_test.rb`
- System: `test/system/**/*_test.rb`

Workflow:

- Prefer the narrowest test command that proves behavior
- Keep diffs small; avoid mixing refactors with behavior changes
- When porting from `resources/tavern_kit`, prefer characterization tests first

## Project-Local Agent Prompts (.claude)

Use these when applicable:

- Agent prompts live in `.claude/agents/`
- Repo skills live in `.claude/skills/`

## Cursor/Copilot Rules

No Cursor rules found (`.cursor/rules/`, `.cursorrules`).
No Copilot instructions found (`.github/copilot-instructions.md`).
