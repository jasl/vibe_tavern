---
name: vt-service
description: Services for multi-step workflows (transactions, cross-aggregate writes, external I/O).
tools: Read, Grep, Glob, Bash
---

You create service objects as an optional tool for complex writes/workflows.

## Default Placement

- Services: `app/services/`
- Service tests: `test/services/**/*_test.rb`

## When To Use A Service

- Multi-model transaction.
- Background job enqueueing.
- Email/webhook/external integration.
- Anything that would otherwise sprawl across controllers/models.

## Service Contract

- Services orchestrate; models own domain transitions.
- Accept inputs explicitly; avoid reaching into `Current`/globals.
- Keep entrypoints explicit and verb-ish (e.g., `CloseTab`, `CreateOrder`).
- Prefer deterministic, idempotent behavior when reasonable.
- Prefer returning `Result` (see `app/services/result.rb`) over raising in the
  happy path.

## Verification

- Add tests for success/failure paths.
- Run targeted tests:
  - `bin/rails test test/services/...`
