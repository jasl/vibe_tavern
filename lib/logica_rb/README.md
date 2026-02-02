# LogicaRb

Core gem: pure Logica -> SQL transpiler for SQLite and PostgreSQL. It does **not** connect to databases or execute SQL by default.

Optional Rails/ActiveRecord integration is available via `require "logica_rb/rails"`.

## Engine support

- Supported: SQLite (`@Engine("sqlite")`), PostgreSQL (`@Engine("psql")`).
- Default engine in LogicaRb: `sqlite` (upstream Logica defaults to `duckdb` when `@Engine` is absent).
- DuckDB is **not** supported here, so any program that resolves to duckdb raises `UnsupportedEngineError("duckdb")`.
- To target PostgreSQL, add `@Engine("psql")`, pass `--engine=psql`, or set user flag `-- --logica_default_engine=psql`.

## CLI usage

```
logica <l file | -> <command> [predicate(s)] [options] [-- user_flags...]
```

Commands:
- `parse`        -> prints AST JSON
- `infer_types`  -> prints typing JSON (psql dialect)
- `show_signatures` -> prints predicate signatures (psql dialect)
- `print <pred>` -> prints SQL (default `--format=script`)
- `plan <pred>`  -> prints plan JSON (alias for `--format=plan`)
- `validate-plan <plan.json or ->` -> validates plan JSON (schema + semantics)

Options:
- `--engine=sqlite|psql`
- `--format=query|script|plan`
- `--import-root=PATH`
- `--output=FILE`
- `--no-color`

Examples:

```bash
exe/logica program.l print Test --engine=sqlite --format=script
exe/logica program.l plan Test
exe/logica validate-plan /tmp/plan.json
exe/logica - print Test -- --my_flag=123
```

Query vs script example:

```bash
cat > /tmp/example.l <<'LOGICA'
@Engine("sqlite");
Test(x) :- x = 1;
LOGICA

exe/logica /tmp/example.l print Test --format=query
```

```sql
SELECT
  1 AS col0
```

```bash
exe/logica /tmp/example.l print Test --format=script
```

```sql
SELECT
  1 AS col0;
```

## Ruby API

```ruby
compilation = LogicaRb::Transpiler.compile_string(
  File.read("program.l"),
  predicate: "Test",
  engine: "sqlite",
  user_flags: {"my_flag" => "123"}
)

sql = compilation.sql("Test", :script)
plan_json = compilation.plan_json("Test", pretty: true)
```

## Rails Integration (optional)

Rails integration is **opt-in** and only loaded after:

```ruby
require "logica_rb"
require "logica_rb/rails"
```

### Configuration

```ruby
# config/initializers/logica_rb.rb
require "logica_rb/rails"

LogicaRb::Rails.configure do |c|
  c.import_root = Rails.root.join("app/logica")
  c.cache = true
  c.cache_mode = :mtime
  c.default_engine = :auto # auto-detect from the ActiveRecord connection
  c.allowed_import_prefixes = ["datasets"] # required for source + allow_imports: true
  c.library_profile = :safe # :safe (default) or :full
  c.capabilities = [] # e.g. [:file_io, :external_exec, :sql_expr] (use with care)
end
```

Configuration API:
- `LogicaRb::Rails.configure { |c| ... }`
- `LogicaRb::Rails.configuration`
- `LogicaRb::Rails.cache` / `LogicaRb::Rails.clear_cache!`

Caching is enabled by default. In Rails development, the Railtie clears the compilation cache on boot and each reload via `ActiveSupport::Reloader.to_prepare`.

### Install generator

```bash
rails g logica_rb:install
```

Creates:
- `app/logica/hello.l`
- `config/initializers/logica_rb.rb`

### Model DSL

```ruby
class User < ApplicationRecord
  logica_query :active_users, file: "users.l", predicate: "ActiveUsers"
end
```

DSL API:
- `logica_query(name, file:, predicate:, engine: :auto, format: :query, flags: {}, as: nil, import_root: nil)`
- `logica(name, connection: nil, **overrides)` (returns `LogicaRb::Rails::Query`)
- `logica_sql`, `logica_result`, `logica_relation`, `logica_records`

### Consumption modes

Relation (recommended, for parameterization via ActiveRecord):

```ruby
rel = User.logica_relation(:active_users)
rel = rel.where("logica_activeusers.age >= ?", 18).order("logica_activeusers.age DESC")
rel.to_a
```

Result (returns `ActiveRecord::Result`, useful when you don't need a model):

```ruby
User.logica_result(:active_users) # => ActiveRecord::Result
```

Records (returns model instances via `find_by_sql`):

```ruby
User.logica_records(:active_users) # => [#<User ...>, ...]
```

Advanced: `User.logica(:active_users)` returns a `LogicaRb::Rails::Query` with `sql`, `plan_json`, `result`, `relation`, `records`, and `cte`.

### External DSL-first API (file / source)

Module-level entrypoints (no model DSL required):

```ruby
# file (recommended default)
q = LogicaRb::Rails.query(file: "hello.l", predicate: "Hello")
q.result # => ActiveRecord::Result

# source (runtime-provided, BI/backoffice custom reports, etc.)
src = <<~LOGICA
  @Engine("sqlite");
  Base(x:) :- x = 11;
  Report(x:) :- Base(x:), x > 10;
LOGICA
q = LogicaRb::Rails.query(source: src, predicate: "Report", trusted: false)
q.result # => ActiveRecord::Result
```

`file:` and `source:` are mutually exclusive (XOR).

### CTE helpers (ActiveRecord `with`)

`LogicaRb::Rails::Query#cte` (and `LogicaRb::Rails.cte`) returns a hash compatible with `ActiveRecord::Relation#with`.

```ruby
cte = LogicaRb::Rails.cte(:adult_users, file: "users.l", predicate: "AdultUsers", model: User)
rel = User.with(cte).joins("JOIN adult_users ON adult_users.id = users.id")
```

### Rake tasks (file workflow)

- `rake logica_rb:validate` scans `app/logica/**/*.l` and compiles all defined predicates.
- `rake logica_rb:print[file,predicate,format]` prints compiled SQL (format: `query|script|plan`).
- `rake logica_rb:signatures[file]` prints `show_signatures` output.

Rake tasks are file-based; `source:` is intended for runtime inputs and is not scanned.

### Safety notes

- The strongest safety guarantees apply to **runtime-provided** `source:` queries in **untrusted** mode (`trusted: false`). For `trusted: true` (or file-based workflows), treat the generated SQL as trusted code.
- This gem provides *guardrails* (SQL validation + allow/deny lists), but **authorization is still your job**: tenant isolation / RLS / data access policies must be enforced by your app + database (roles, GRANTs, RLS, views, etc).
- `LogicaRb::Rails::Query#relation` uses `Arel.sql` to wrap the compiled subquery. Treat compilation output as trusted code, and do **not** pass untrusted user input into Logica flags without validation.
- `ActiveRecord::Relation#with` also accepts `Arel.sql(...)` for SQL literals, but this must only wrap known-safe SQL. Do not interpolate request params/model attributes/etc. into SQL strings.
- Default `library_profile: :safe` excludes Logica library rules that perform file IO / external execution / console side effects. Enable explicitly via `LogicaRb::Rails.configure { |c| c.library_profile = :full }` (or per-query `library_profile: :full`) only when you trust the source.
- For runtime-provided `source:` with `trusted: false`, `SqlExpr` and other dangerous built-ins are rejected by default. If you intentionally need them, you must opt in explicitly via `capabilities:` (e.g. `capabilities: [:sql_expr]`).
- Rails `prevent_writes` is a client-side safeguard to reduce accidental writes; it is **not** a substitute for DB-level read-only enforcement.

### BI/后台自定义查询（source 模式）

`source:` is a first-class API, but defaults to a safer mode:

- `trusted: false` by default
- query-only: `format` must be `:query` unless `trusted: true`
- imports disabled: `allow_imports` defaults to `false` unless `trusted: true` (or `allow_imports: true` explicitly)
- query-only validation raises `LogicaRb::SqlSafety::Violation`

#### BI / Untrusted Quickstart (copy-paste)

```ruby
src = <<~LOGICA
  @Engine("psql");
  Report(id:) :- customers(id:);
LOGICA

policy = LogicaRb::AccessPolicy.untrusted(
  allowed_relations: ["customers", "orders"] # or "public.customers"/"public.orders" (recommended for Postgres)
)

q = LogicaRb::Rails.query(source: src, predicate: "Report", trusted: false, access_policy: policy)
q.result
```

- Default untrusted `allowed_functions` profile: `:rails_minimal_plus` (`count`, `sum`, `avg`, `min`, `max`, plus `cast`, `coalesce`, `nullif`).
- Switch to stricter `:rails_minimal`: set `LogicaRb::Rails.configure { |c| c.untrusted_function_profile = :rails_minimal }` (or build the policy with `function_profile: :rails_minimal`).
- Extend the allowlist explicitly per query (example: `lower`, `upper`, `strftime`, `date_trunc` must be opted in; see below).

Operational safety suggestions for runtime-provided source:

- Use a read-only DB role and restrict accessible schemas/tables.
- Set timeouts / statement limits (e.g., PostgreSQL `statement_timeout`).
- Do not splice request params directly into Logica source or `flags` without validation.
- PostgreSQL: avoid granting roles like `pg_read_server_files` / `pg_execute_server_program` and avoid superuser for apps serving untrusted queries.
- SQLite: do not enable extension loading, and consider SQLite defensive mode when validating untrusted SQL (if available in your SQLite build).

Configure the untrusted function profile (Rails integration):

```ruby
LogicaRb::Rails.configure do |c|
  # :rails_minimal (stricter) or :rails_minimal_plus (default)
  c.untrusted_function_profile = :rails_minimal_plus
end
```

Extend the allowlist for specific queries:

```ruby
require "set"

base = LogicaRb::AccessPolicy.untrusted(allowed_relations: ["events"])
allowed = base.resolved_allowed_functions(engine: "psql") || Set.new
policy = base.with(allowed_functions: allowed | Set["lower", "upper", "date_trunc"])

q = LogicaRb::Rails.query(source: src, predicate: "Report", trusted: false, access_policy: policy)
q.result
```

Dangerous functions are always forbidden (denylist wins), even if misconfigured into an allowlist (e.g. SQLite `load_extension`, Postgres `pg_read_file`, `lo_import`, `dblink_connect`, ...).

#### PostgreSQL pg_catalog/search_path 注意事项

- `pg_catalog` is always searched via `search_path` in PostgreSQL.
- Unqualified `pg_*` relation names can resolve to system catalogs (e.g. `pg_class` -> `pg_catalog.pg_class`).
- For untrusted validation, LogicaRb rejects unqualified `pg_*` relations. Fix: explicitly schema-qualify (e.g. `public.pg_class`) and allow it explicitly, or rename the table.

Plan docs:
- `docs/PLAN_SCHEMA.md`
- `docs/plan.schema.json`
- `docs/EXECUTOR_GUIDE.md`

## Development

```bash
bundle exec rake test
bundle exec rake goldens:generate
```

### DB smoke tests

These tests validate that generated SQL/Plan is executable in real databases (no result assertions; just “no error”).

SQLite:

```bash
bundle exec rake test:db_smoke_sqlite
```

Postgres (requires a reachable database):

```bash
export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/postgres
bundle exec rake test:db_smoke_psql
```

## License

Apache-2.0. See `LICENSE.txt`.
