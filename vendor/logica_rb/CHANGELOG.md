# Changelog

## 0.1.0

### Added

- Logica -> SQL transpiler for SQLite and PostgreSQL (Ruby 3.4+).
- `logica` CLI (`exe/logica`) and optional Rails/ActiveRecord integration.
- `SECURITY.md` and `docs/security_model.md`.
- `rake release:sanity` packaging/install smoke task.

### Security

- Untrusted `source:` mode guardrails (query-only validation, relation/function allow/deny lists, import whitelist for `allow_imports: true`).
- Security-module coverage threshold (`SqlSafety` + `SourceSafety` >= 95%).
