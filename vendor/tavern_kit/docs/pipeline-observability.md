# Pipeline Observability & Debugging Guide

This document standardizes prompt-build observability for the new
`PromptBuilder -> Pipeline -> Step` architecture.

Scope:
- `TavernKit::PromptBuilder`
- `TavernKit::PromptBuilder::Pipeline`
- `TavernKit::PromptBuilder::Step`
- `TavernKit::PromptBuilder::State`
- `TavernKit::PromptBuilder::Instrumenter::*`

## Core Concepts

### 1) `Context` vs `State`

- `PromptBuilder::Context` is the developer-facing input container.
  - Holds request input/config and optional `module_configs` step overrides.
- `PromptBuilder::State` is the internal mutable build workspace.
  - Steps read/write intermediate fields (`blocks`, `outlets`, `lore_result`, `plan`, ...).

`Pipeline#call` always executes on `State`.

### 2) Context payload contract

`state.context` is the application-owned per-build context payload.

- Context can be a typed context object (e.g. `RisuAI::Context`) or a
  `PromptBuilder::Context` generated from a Hash.
- Context is passed from app/runner to steps; steps should treat it as
  read-mostly input and avoid replacing it after normalization.
- Context should not be stored in state metadata (`state[:context]`) as a
  fallback path.

### 2.1) Step config resolution contract

- Step defaults are defined at pipeline wiring time (`use_step ...` options).
- Per-run overrides are supplied via `context.module_configs[step_name]`.
- `Pipeline` deep-merges defaults + overrides and then resolves typed config
  via step-local parser (`Step::Config.from_hash` or step-specific builder).
- Unknown step keys in `context.module_configs` are ignored.
- Known step config parse errors are treated as programmer errors (fail-fast).

### 3) Warnings are first-class

Use `state.warn("...")` for expected external-input issues.

- Tolerant mode: warning is collected (`state.warnings`) and build continues.
- Strict mode: `state.warn` raises `TavernKit::StrictModeError`.

### 4) Instrumentation is optional

`state.instrumenter` is `nil` by default. When set, steps emit structured events.

Built-in collector:
- `PromptBuilder::Instrumenter::TraceCollector`

Event contract:
- `:step_start` (`name:`)
- `:step_finish` (`name:`)
- `:step_error` (`name:`, `error:`)
- `:warning` (`message:`, `step:`)
- `:stat` (`key:`, `value:`, `step:`)

## Recommended Debug Flow

```ruby
instrumenter = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new

plan =
  TavernKit::SillyTavern.build do
    strict true
    instrumenter instrumenter
    # ... other inputs
  end

trace = instrumenter.to_trace(fingerprint: plan.fingerprint(dialect: :openai))
```

Recommended inspection order:
1. `plan.debug_dump`
2. `plan.trim_report`
3. `trace`
4. `plan.fingerprint(...)`

## Step Authoring Checklist

- Prefer `state.warn` (not `raise`) for expected external input failures.
- Keep expensive instrumentation lazy via `state.instrument { ... }` blocks.
- Emit local counters with `state.instrument(:stat, step: ..., key: ..., value: ...)`.
- Do not mix transport/protocol concerns into prompt-building steps.
