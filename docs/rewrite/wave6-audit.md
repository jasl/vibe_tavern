# Wave 6 Audit Notes (2026-02-02)

This note captures the final "global consistency / security / performance"
audit outcomes before moving on to post-rewrite backlogs.

It is intentionally short and operational: what we audited, what we changed,
and what remains as explicit decisions/backlogs.

## Gates (must stay green)

- `cd lib/tavern_kit && bundle exec rake test`
- `bin/rubocop`
- `ruby bin/lint-eof`
- Periodically: `bin/ci`

## Consistency (API + naming)

- **Canonical keys at boundaries**:
  - Use `TavernKit::Utils::HashAccessor` when parsing mixed-key external hashes
    (string/symbol, camelCase/snake_case) to avoid ad-hoc `h[:x] || h["x"]`.
  - Platform runtime input is normalized once at pipeline entry (snake_case
    symbol keys) so downstream code can rely on a stable shape.
- **VariablesStore** is the standard name for ST `var`/`globalvar` and RisuAI
  extensions (session-level state). The older "ChatVariables/Store" naming is
  removed from the public surface.
- **Runtime** is application-owned per-build state (chat indices, toggles,
  metadata). It is set once on `ctx.runtime` and must not be replaced during
  middleware execution.

## Security hardening

- **ZIP-based formats** (.byaf/.charx):
  - All reads go through `TavernKit::Archive::ZipReader` which enforces:
    entry count, per-entry size, total read budget, path traversal rejection,
    compression ratio limit, and encrypted-entry rejection.
  - Ingested assets support lazy reads and allow downstream apps to enforce
    `max_bytes` per read.
- **Regex safety**:
  - No regex timeouts (to avoid global/thread side effects).
  - Basic guardrails via `TavernKit::RegexSafety`:
    pattern size limit + input size limit, tolerant-by-default behavior.

## Performance notes (low-risk wins already applied)

- Bounded caches (thread-safe via `Mutex`):
  - `TavernKit::LRUCache`
  - `TavernKit::JsRegexCache` (JS regex literal -> Ruby Regexp conversion)
  - `TavernKit::Trimmer` token estimate memoization (bounded, digest for large strings)
- Debug/trace work is opt-in via `ctx.instrumenter` (do not pay overhead by default).

## Remaining decisions / explicit non-goals

- `runtime.metadata` / `runtime.toggles` remain plain Hashes for now (a future
  unification into Stores is deferred).
- UI directives / CLI tooling are tracked in `docs/rewrite/backlogs.md`
  (explicitly out of the rewrite plan).

