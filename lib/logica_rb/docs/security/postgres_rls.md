# Postgres RLS deployment template (LogicaRb / untrusted BI queries)

This gem provides *guardrails* (compile-time + SQL validators), but **PostgreSQL must remain the final security boundary**.

## Recommended shape

1) **Separate roles**

- `app_owner` (migration/DDL owner)
- `app_rw` (normal app runtime)
- `bi_ro` (untrusted / BI runtime; *no writes*)

2) **Expose only an allowlist**

- Put BI-exposed relations in a dedicated schema (example: `bi`).
- Prefer **views** over raw tables, so the BI surface is explicit and stable.
- `GRANT USAGE ON SCHEMA bi TO bi_ro;`
- `GRANT SELECT ON ALL TABLES IN SCHEMA bi TO bi_ro;` (and/or explicit GRANTs)

3) **Tenant isolation via RLS**

Enable RLS and create policies on the underlying tables (or on `bi` tables if you materialize there):

```sql
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON public.orders
  USING (tenant_id = current_setting('app.tenant_id', true)::int);
```

4) **Force RLS**

Table owners can bypass RLS unless forced. In most apps you want RLS to apply even to the owner role:

```sql
ALTER TABLE public.orders FORCE ROW LEVEL SECURITY;
```

5) **Set tenant context from the runner, not from user SQL**

User SQL should not be able to run `SET`, `set_config(...)`, etc. Set tenant context at execution time:

```sql
BEGIN;
  SET LOCAL app.tenant_id = '42';
  -- execute BI query here
COMMIT;
```

## Postgres foot-guns to avoid

- Do **not** grant `BYPASSRLS` to the BI role.
- Do **not** grant high-privilege predefined roles such as `pg_read_server_files`, `pg_write_server_files`, `pg_execute_server_program` (and similar) to the BI role.
- Views: on **Postgres 15+**, prefer `CREATE VIEW ... WITH (security_invoker = true)` so view execution uses the invoker’s privileges (reduces surprises around view ownership and privilege escalation when combined with RLS).

## Rails notes

Rails `prevent_writes` is a **client-side safeguard**. It helps avoid accidental writes, but you still need DB-level read-only enforcement (role + GRANTs + RLS) for untrusted SQL execution.
