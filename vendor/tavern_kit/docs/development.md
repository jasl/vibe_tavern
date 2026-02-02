# Development Notes (Gem)

This doc is for developing the embedded `tavern_kit` gem in this repo.

## Golden Commands

From repo root:

- `bin/rubocop`
- `ruby bin/lint-eof`

From the gem root (`vendor/tavern_kit/` in this repo):

- `bundle exec rake` (gem tests + gem rubocop)
- `bundle exec rake test` (gem tests only)
- `bundle exec rake test:guardrails` (ST contract + parity guardrails)
- `bundle exec rake test:conformance` (CCv2/CCv3 conformance tests)
- `bundle exec rake test:integration` (end-to-end build tests)
- `bundle exec rake test:risuai` (RisuAI characterization + integration)

## Testing Philosophy

- Prefer characterization/contract tests for behavior that must match upstream
  (SillyTavern/RisuAI), with pinned source references in test headers.
- Prefer conformance tests for spec-level behavior (CCv2/CCv3).
- Keep `strict` mode for tests/debug; keep tolerant defaults for untrusted input.
