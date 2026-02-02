# Security Model (v0.1.x)

## Goal

LogicaRb aims to make it hard to accidentally compile/execute *dangerous SQL* or *over-broad reads* when compiling **runtime-provided Logica source** (e.g. BI / backoffice custom reports).

The core gem does not execute SQL; the optional Rails integration adds “compile + run” helpers.

## Threat model (what we protect against)

When `source:` is provided at runtime in **untrusted** mode (`trusted: false`), we want to prevent:

- **Multi-statement execution** and non-query statements (DDL/DML/transactions/session changes)
- **Dangerous SQL functions** (file reads, extension loading, dblink, admin/DoS primitives, …)
- **Unauthorized relation access** (reading from system catalogs or non-allowlisted tables/schemas)
- **Import-based escalation** (pulling in unreviewed Logica code via `import`)
- **Logica builtins with side effects** in untrusted sources (`SqlExpr`, file IO, external exec, console)

## Non-goals

- Tenant isolation / row-level security / column-level security
- Protecting a database with a privileged credential from all possible expensive queries (DoS)
- Fully parsing SQL with a complete SQL grammar

You should still:
- Use a read-only DB role where possible
- Apply timeouts / statement limits at the DB level
- Use RLS/views/GRANTs to enforce data access

## Controls

### Untrusted `source:` (Rails integration)

Default posture for `source:` is intentionally stricter than for file-based workflows:

1) **Source safety**
- Rejects dangerous Logica builtins (e.g. `SqlExpr`, `ReadFile`, `RunClingo`, `PrintToConsole`) unless explicitly enabled via `capabilities:`.
- Rejects user-provided `@Ground` declarations unless `:ground_declarations` capability is enabled.

2) **Query-only SQL validation**
- Rejects multi-statement SQL (e.g. `;` outside of strings/comments).
- Rejects non-query statements and session-affecting keywords.
- Engine-specific blocks for SQLite (`ATTACH`, `PRAGMA`, …) and Postgres (`COPY`, `DO`, …).

3) **Denylist (always wins)**
- Known dangerous functions are forbidden even if misconfigured into an allowlist.
- Quoted identifiers and schema-qualified calls must not bypass the denylist.

4) **Function allowlist**
- Default profile is `:rails_minimal_plus` (`count`, `sum`, `avg`, `min`, `max`, plus `cast`, `coalesce`, `nullif`).
- Common functions like `lower`/`upper`/`date_trunc` must be explicitly allowlisted.

5) **Relation/schema allowlist + denied schemas**
- Denied schemas (e.g. `pg_catalog`, `information_schema`, `sqlite_master`) always win.
- For Postgres, unqualified `pg_*` relation names are rejected to avoid `search_path` resolving to system catalogs.

6) **Imports whitelist**
- Imports are disabled by default.
- If `allow_imports: true` is used for untrusted `source:`, `allowed_import_prefixes` must be configured and every import must match the whitelist.

### SQLite runtime hardening (optional)

If using the SQLite executor/authorizer helpers, LogicaRb can additionally:
- Run queries under a SQLite authorizer
- Harden connection pragmas (`query_only=1`, `trusted_schema=0`) within a block and restore them afterward (even on exceptions)

## Ruby ↔ Python parity

`script/python_parity.sh` compares upstream Python Logica output (pinned by `UPSTREAM_LOGICA_COMMIT`) against this repository’s golden SQL, using `test/fixtures_manifest.yml` as the single source of truth.

Any intentional differences should be explicitly documented and allowlisted.
