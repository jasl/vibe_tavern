# Plan Schema (v1)

The LogicaRb plan is a deterministic, engine-specific execution plan derived from compiled Logica programs. LogicaRb is a transpiler: it does not execute SQL. Instead, it emits a Plan JSON that an external driver can execute.

## Top-level fields

- `schema`: Fixed string `"logica_rb.plan.v1"`.
- `engine`: `"sqlite"` or `"psql"`.
- `final_predicates`: Array of final predicate names in the order they were compiled.
- `outputs`: Array describing what the compilation should export to the caller (stable order, 1:1 with `final_predicates`).
- `preambles`: Array of SQL scripts to run once before any actions (unique, stable order).
- `dependency_edges`: Array of `[source, target]` predicate dependencies.
- `data_dependency_edges`: Array of `[source, target]` data dependencies.
- `iterations`: Map of iteration name -> iteration configuration.
- `config`: Array of action entries in deterministic order.

## `outputs`

Each output entry has:

- `predicate`: The user-facing predicate name requested by the caller.
- `node`: The concrete plan node name that materializes that predicate (may differ when internal `down_` renaming is applied).
- `kind`: Currently always `"table"`.

## `validate-plan` (CLI)

You can validate a plan JSON file (or stdin) against the Plan v1 structural and semantic rules:

```sh
logica validate-plan <plan.json or ->
```

Behavior:
- Success: prints `OK` to stdout and exits `0`.
- Failure: prints a human-locatable error message to stderr and exits `1`.

Common failure examples:
- Missing required field (e.g. `outputs`, `config`, `iterations`).
- `outputs` references a node that does not exist in `config`.
- Dependency cycle / deadlock (including iteration groups treated as macro-nodes).

## `iterations`

Each iteration entry has:

- `predicates`: Ordered list of predicate (node) names to execute each round.
- `repetitions`: Maximum number of rounds.
- `stop_signal`: File path; if the file exists and is non-empty, the iteration stops early.

## `config` entries

Each entry has:

- `name`: Predicate or data name.
- `type`: `"data"`, `"intermediate"`, or `"final"`.
- `requires`: Array of dependency names (sorted, unique).
- `action`:
  - `predicate`: Predicate name (mirrors `name`).
  - `launcher`: `"none"` for data nodes, `"query"` for SQL execution.
  - `engine`: Present only for `launcher="query"`.
  - `sql`: SQL script to execute for the predicate (present only for `launcher="query"`).

## Determinism rules

- `config` order is stable: sorted by `type` (data, intermediate, final) then by `name`.
- `requires` arrays are sorted.
- `dependency_edges` and `data_dependency_edges` are sorted lexicographically.
- `preambles` preserve first-seen order across compilations.
- `outputs` preserve `final_predicates` order.

## External Driver / Executor Reference (minimal)

### A) Minimal DB Adapter Contract (language-agnostic)

Any external driver (Ruby/Go/Node/Python/etc.) should implement:

```
interface DbAdapter:
  # Executes a SQL script that may contain multiple statements.
  # Must execute statements sequentially on the SAME connection/session.
  exec_script(sql_script: String) -> void

  # Optional (only if caller wants results programmatically):
  # Executes a single query and returns rows as arrays or dicts.
  query(sql_query: String) -> Array<Row>

  # Optional: transaction helpers (recommended, but engine-dependent):
  begin_transaction() -> void
  commit() -> void
  rollback() -> void
```

Notes:
- The transpiler does NOT split SQL statements reliably for you.
  Drivers SHOULD prefer their DB library's "execute script/batch" method.
- If splitting is required, splitting must be SQL-aware (strings, comments, dollar-quoting for Postgres).

### B) Plan Semantics (what "name", "requires", "action.sql" mean)

- Plan.config is a list of nodes. Each node has:
  - name: String
  - type: "data" | "intermediate" | "final"
  - requires: [String] dependencies by node name
  - action:
      - launcher: "none" | "query"
      - sql: SQL script (only when launcher="query")
- A node with launcher="none" represents pre-existing data:
  The driver MUST treat it as already satisfied/completed without executing SQL.
- For launcher="query":
  action.sql MUST be executed exactly as-is (as a SQL script).
  The script is assumed to create/update the relation referenced by node.name
  (or at least make it available for downstream nodes as referenced in their SQL).
- Plan.preambles is a list of SQL scripts to run ONCE each before executing nodes.
  Preambles can contain type declarations, helper functions, TEMP objects, etc.

### C) Iterations / Deep Recursion Semantics

Plan.iterations is a dict of iteration groups. Each group has:
- predicates: [String]  # ordered list of node names to execute per iteration step
- repetitions: Integer  # max number of rounds
- stop_signal: String   # file path (may be empty)

Iteration execution rule:
- Before each round:
  - If stop_signal is non-empty and exists, delete it (reset).
- Execute all predicates listed in the group, in the given order:
  - For each predicate name, find corresponding node in Plan.config and exec its action.sql.
- After the round:
  - If stop_signal is non-empty AND file exists AND file size > 0:
      break early (converged).

If driver does not support stop_signal semantics, it MAY ignore stop_signal and just run exactly `repetitions` rounds.

### D) Reference Executor Pseudocode (sequential, deterministic)

This pseudocode is intentionally simple and sequential. A real driver MAY parallelize nodes when dependencies allow, but must preserve correctness.

Definitions:
- nodes = { node.name => node } from Plan.config
- member_of_iter = map predicate_name -> iter_name if present in iterations

Helper:
- is_data_node(name):
    return nodes[name].action.launcher == "none"

# A dependency "dep" is satisfied if:
# - dep is a data node (launcher=none), OR
# - dep is a non-iterative node that has been executed, OR
# - dep belongs to an iteration group that has completed
function dep_satisfied(dep, done_nodes, done_iters):
  if is_data_node(dep): return true
  if dep in done_nodes: return true
  if dep in member_of_iter and member_of_iter[dep] in done_iters: return true
  return false

Build iteration groups:
for each iter_name, spec in plan.iterations:
  iter_members[iter_name] = spec.predicates (preserve order)
  # compute external deps for the whole group:
  # union of requires of each member node, excluding dependencies within the group
  external_deps[iter_name] = sorted_unique(
    flatten([nodes[p].requires for p in iter_members[iter_name]])
    minus iter_members[iter_name]
  )

Execution:
function execute_plan(plan, adapter):
  # 1) Preambles
  for sql in plan.preambles:
    if sql is not blank:
      adapter.exec_script(sql)

  # 2) Mark data nodes as done "implicitly"
  done_nodes = set()
  for node in plan.config:
    if node.action.launcher == "none":
      done_nodes.add(node.name)

  done_iters = set()

  # 3) Execute until all non-iter nodes and all iter groups are done
  while true:
    progressed = false

    # 3a) Run any ready NON-ITERATIVE node (once)
    for node in plan.config in stable order:
      if node.name in done_nodes: continue
      if node.name in member_of_iter: continue  # iter members handled by group
      if all(dep_satisfied(dep, done_nodes, done_iters) for dep in node.requires):
        if node.action.launcher == "query":
          adapter.exec_script(node.action.sql)
        done_nodes.add(node.name)
        progressed = true

    if progressed:
      continue

    # 3b) Run any ready ITERATION GROUP (once to convergence)
    for iter_name in plan.iterations keys in stable order:
      if iter_name in done_iters: continue
      if all(dep_satisfied(dep, done_nodes, done_iters) for dep in external_deps[iter_name]):
        spec = plan.iterations[iter_name]

        for round in 1..spec.repetitions:
          if spec.stop_signal != "":
            delete_file_if_exists(spec.stop_signal)

          for pred in spec.predicates:
            node = nodes[pred]
            # assume plan is valid: node.action.launcher is "query"
            adapter.exec_script(node.action.sql)

          if spec.stop_signal != "" and file_exists(spec.stop_signal) and file_size(spec.stop_signal) > 0:
            break

        done_iters.add(iter_name)
        progressed = true

    if progressed:
      continue

    # 3c) Check completion or deadlock
    all_non_iter_done = all(
      (n.action.launcher == "none") or (n.name in done_nodes) or (n.name in member_of_iter)
      for n in plan.config
    )
    all_iters_done = (size(done_iters) == number_of_iteration_groups)

    if all_non_iter_done and all_iters_done:
      break
    else:
      raise Error("Plan execution deadlock/cycle: no ready nodes or groups")

### E) SQL Script Execution Advice (for driver authors)

- Prefer DB library support:
  - SQLite: "executescript" style APIs
  - Postgres: many drivers allow executing multi-statement text; otherwise split carefully
- If you must split:
  - Ignore semicolons inside:
      - single-quoted strings
      - double-quoted identifiers
      - Postgres dollar-quoted strings ($$...$$, $tag$...$tag$)
      - comments (-- ... endline, /* ... */)
- Always run scripts on the same session/connection (TEMP objects, search_path, etc.).

### F) Observability (recommended)

Drivers should log:
- node name
- iteration group + round number (if applicable)
- execution time
- (optional) hash(sql) instead of full SQL for large scripts

### G) What the transpiler guarantees vs. what drivers must do

Transpiler guarantees:
- deterministic plan JSON ordering (sorted keys, stable arrays)
- stable sql/script output for the chosen engine (sqlite/psql)
- plan includes all required dependencies and iteration metadata

Drivers must:
- execute scripts in order and obey dependencies
- manage connections/transactions/credentials
- fetch/return final results if needed (plan marks "final" nodes)
