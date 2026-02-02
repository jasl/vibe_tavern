# Dummy BI demo

This is a small Rails app living inside `logica_rb` to demonstrate:

- file-mode reports (`Report.mode = file`, compiled from `dummy/app/logica`)
- source-mode “BI / backoffice” custom queries (`trusted: false`)
- pagination + safe defaults for untrusted execution

## Setup

```bash
cd dummy
bin/rails db:migrate
bin/rails db:seed:replant
bin/rails server
```

Then open `http://localhost:3000`.

## Reset + seed (deterministic)

Reset all tables and re-run seeds:

```bash
cd dummy
bin/rails db:seed:replant
```

Control scale + seed (all deterministic for a given `BI_SEED`):

```bash
cd dummy
BI_CUSTOMERS=200 BI_ORDERS=5000 BI_SEED=7 bin/rails db:seed:replant
```

Convenience tasks:

```bash
cd dummy
bin/rake bi:seed
bin/rake bi:seed:large
```

Quick manual verification:

- Open `/reports` and run a report; the result + row count should match the seeded scale.

## Pages

- `/reports` — list reports
- `/reports/:id` — run a saved report (flags + pagination) and see run history
- `/custom_queries` — run a source-mode query (untrusted) and optionally save it as a report

## Isolated plan execution (Postgres)

For trusted file-mode reports, the UI can run the compiled plan in an isolated temporary schema:

- transaction (`requires_new: true`)
- `CREATE SCHEMA logica_tmp_xxx`
- `SET LOCAL search_path TO logica_tmp_xxx, public`
- run plan preambles + nodes
- ensure `DROP SCHEMA ... CASCADE`

This is implemented in `dummy/app/services/bi/isolated_plan_runner.rb`.

## Safety defaults (source + trusted=false)

When a report is `source` mode and `trusted: false`, execution is hardened:

- Query-only SQL validation (blocks multi-statement and common DDL/DML keywords)
- Imports disabled by default (`allow_imports: false`)
- `prevent_writes` wrapper (uses `connected_to(role: :reading, prevent_writes: true)` when available, otherwise `while_preventing_writes`)
- SQLite (untrusted): `PRAGMA query_only = 1`, `PRAGMA trusted_schema = 0` (restored after execution) — reduces write/schema attack surface
- PostgreSQL (inside a transaction): `SET LOCAL statement_timeout`, `SET LOCAL lock_timeout`, `SET LOCAL idle_in_transaction_session_timeout` (env: `BI_IDLE_IN_TX_TIMEOUT_MS`), `SET LOCAL transaction_read_only = on`
- Max rows cap (default `1000`) enforced via `LIMIT/OFFSET` pagination wrapper

## Production recommendations (Postgres)

If you deploy the “untrusted BI query” pattern on PostgreSQL, read the short hardening checklist:

- `../docs/security/postgres_hardening.md`

To enable imports for source-mode reports, the app must configure a whitelist:

```ruby
# dummy/config/initializers/logica_rb.rb
LogicaRb::Rails.configure do |c|
  c.allowed_import_prefixes = ["datasets"]
end
```

## Flags schema (`flags_schema`)

Reports can define `flags_schema` (JSON) to validate flags before compilation/execution.

Example:

```json
{
  "min_total_cents": { "type": "integer", "min": 0 },
  "status": { "type": "enum", "values": ["placed", "shipped", "delivered", "refunded"] },
  "from_date": { "type": "date" }
}
```

Unknown keys are rejected for reports with a schema.
