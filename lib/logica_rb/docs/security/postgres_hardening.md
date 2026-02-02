# PostgreSQL hardening (BI / untrusted execution)

This repo supports PostgreSQL for untrusted “BI / backoffice” style queries. The goal is to reduce blast radius if a user manages to run unexpected SQL or if a trusted dependency executes unsafe SQL in the same session.

## 1) Lock down `public` schema

On many clusters, the `public` schema is writable by everyone via the `PUBLIC` pseudo-role. That means any role can create objects (tables, functions, operators) in `public`.

For BI/untrusted execution, prefer:

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Why: it reduces “upgrade/library risk”. If some dependency runs `CREATE FUNCTION ...` (or an attacker finds a path to it), it can’t silently plant objects in a globally searched schema.

## 2) `pg_catalog` is always searched

PostgreSQL effectively searches `pg_catalog` even if you don’t include it in `search_path`. This is convenient, but it also means that **unqualified** names (especially `pg_*`) can unexpectedly resolve to system catalog relations/functions.

Practical takeaway:

- Avoid relying on `pg_*` unqualified identifiers in untrusted SQL.
- Prefer schema-qualified names like `public.some_table` instead of `some_table` when writing allowlists and when generating SQL.

## 3) Read-only role + RLS (principle)

For production BI:

- Use a dedicated **read-only** role for query execution.
- Enforce tenant isolation with **Row Level Security (RLS)**.
- Pass tenant context via a session/transaction variable (e.g. `SET LOCAL app.tenant_id = '...'`) and reference it in RLS policies.

Keep “who can read what” in the database (RLS + grants), and keep the app responsible only for selecting the right tenant context and applying timeouts.
