# Pipeline Observability & Debugging Guide

This document standardizes how to debug prompt builds in TavernKit, without
adding meaningful overhead to production runs.

Scope:
- `TavernKit::Prompt::Pipeline`
- `TavernKit::Prompt::Context`
- `TavernKit::Prompt::Instrumenter::*`
- strict vs tolerant error/warn behavior

## Core Concepts

### 1) Context is the build workspace

`Prompt::Context` is mutable working memory that flows through each middleware.

- Inputs live on `ctx` (character/user/history/preset/runtime/etc)
- Middlewares write intermediate state onto `ctx` (`blocks`, `outlets`, `lore_result`, ...)
- The final output is `ctx.plan` (`Prompt::Plan`)

### 2) Runtime is app-owned state (sync contract)

`ctx.runtime` is the application-owned state snapshot that must stay in sync
with prompt building (chat indices, app metadata, feature toggles, etc).

- Runtime must not be replaced once set (enforced by `Context#runtime=`).
- Runtime should be treated as immutable during pipeline execution.

### 3) Warnings are first-class (tolerant by default)

Prompt building contains user-supplied inputs. For *expected* issues (invalid
macros, malformed entries, unsupported regexes, etc), prefer warnings instead
of raising exceptions.

- `ctx.warn("...")` appends to `ctx.warnings`
- In strict mode (`ctx.strict = true`), `ctx.warn` raises `StrictModeError`

Use strict mode for tests/debugging to surface “tolerant” failures.

### 4) Instrumentation is optional (nil means near-zero overhead)

`ctx.instrumenter` is `nil` by default. When present, middlewares can emit
debug events. When absent, instrumentation should cost ~0.

Built-in implementation:
- `Prompt::Instrumenter::TraceCollector`

Event contract (see `lib/tavern_kit/prompt/instrumenter.rb`):
- `:middleware_start` (name:)
- `:middleware_finish` (name:, stats: optional)
- `:middleware_error` (name:, error:)
- `:warning` (message:, stage: optional)
- `:stat` (key:, value:, stage: optional)

## Recommended Debug Pattern

### Enable instrumentation (debug build)

```ruby
instrumenter = TavernKit::Prompt::Instrumenter::TraceCollector.new

plan =
  TavernKit::SillyTavern.build do
    strict true                  # optional: fail-fast on warnings
    instrumenter instrumenter    # collect per-stage trace

    # ... other DSL inputs
  end

plan.trace          # => Prompt::Trace (for ST builds)
plan.trim_report    # => Prompt::TrimReport (when trimming is used)
plan.debug_dump     # => string dump of blocks
```

Notes:
- Some pipelines attach `plan.trace` automatically only in specific stages
  (e.g. ST attaches it after trimming). If you need a trace in other pipelines,
  you can call `instrumenter.to_trace(fingerprint: plan.fingerprint(...))`
  in the application layer.

### Use lazy instrumentation payloads

`Context#instrument` supports a block for lazy payload evaluation:

```ruby
ctx.instrument(:stat, stage: :lore, key: :activated_count, value: count)

ctx.instrument(:debug, stage: :lore) do
  { expensive_dump: compute_big_hash(ctx) } # only runs when instrumenter is set
end
```

This keeps the default production path fast.

## Failure Semantics (Standard)

### Expected problems

Use `ctx.warn` for expected issues:
- invalid/unparseable user content
- unknown/unsupported macros that should be preserved
- regex skipped due to safety limits

Behavior:
- tolerant mode: warning is collected and the pipeline continues
- strict mode: `StrictModeError` is raised immediately

### Unexpected problems (bugs / programmer errors)

Raise exceptions. The middleware base will wrap them as `PipelineError` with
the stage name attached, so downstream apps get a stable failure anchor:

- `TavernKit::PipelineError` includes `stage:`

## “Why This Prompt?” Playbook

When debugging a prompt build, prefer this fixed path:

1) `plan.debug_dump` (see every block, including disabled)
2) `plan.trim_report` (evictions, token totals, budgets)
3) `plan.trace` (per-stage durations, per-stage warnings, stage stats)
4) `plan.fingerprint(...)` (useful as a cache key and repro identifier)

## Middleware Authoring Checklist

- Use `ctx.warn` (not `raise`) for expected invalid external input.
- Wrap expensive debug payloads in `ctx.instrument { ... }`.
- Emit stage-local counters via `ctx.instrument(:stat, stage: ..., key: ..., value: ...)`.
- Never replace `ctx.runtime` / `ctx.variables_store` once set.
