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

### 2) Runtime payload contract

`state.runtime` is the application-owned per-build runtime payload.

- Runtime can be a typed runtime object (e.g. RisuAI runtime contract) or a
  `PromptBuilder::Context` generated from a Hash.
- Runtime is passed from app/runner to steps; steps should treat it as
  read-mostly input and avoid replacing it after normalization.

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
