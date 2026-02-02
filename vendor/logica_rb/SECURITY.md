# Security Policy

## Reporting a vulnerability

Please report security issues privately by opening a GitHub Security Advisory (preferred) or by emailing the maintainer listed in the gemspec.

Include:
- A minimal reproduction (Logica source and generated SQL, if applicable)
- The engine (`sqlite` / `psql`)
- Whether the source is treated as `trusted` or `untrusted`
- The access policy used (allowed relations/functions, capabilities)

## Scope and guarantees

LogicaRb is a Logica → SQL/Plan transpiler. The core gem does **not** execute SQL.

Security-sensitive behavior is primarily in the optional Rails integration when compiling **runtime-provided** `source:` in **untrusted** mode:
- Query-only validation (rejects multi-statement and non-SELECT statements)
- Dangerous SQL keyword/function denylist (denylist always wins)
- Function allowlist (default profile is `:rails_minimal_plus`)
- Relation/schema allowlist + denied system schemas/catalogs
- Imports are disabled by default; enabling `allow_imports: true` requires a configured prefix whitelist

This gem does **not** implement tenant/row/column authorization. Enforce authorization in your app + database (roles/GRANTs/RLS/views).

See `docs/security_model.md` for the threat model and operational guidance.
