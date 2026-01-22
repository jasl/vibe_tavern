---
name: vibe-tavern-guardrails
description: Condensed guardrails for the Vibe Tavern Rails rewrite.
---

# Vibe Tavern Guardrails

This codebase is a rewrite target for `/Users/jasl/Workspaces/tavern_kit/playground`.
The goal is to reduce "vibe coding" churn by enforcing consistent boundaries
and test-driven feedback.

## Non-Negotiables

- Do not guess file locations or patterns. Search (`Grep/Glob`) and read first.
- Prefer small, reviewable diffs. Avoid mixing refactors with behavior changes.
- Use Minitest + fixtures (no RSpec).
- Use the smallest architectural tool that fits (model/concern first).
- Run the narrowest relevant `bin/rails test ...` before claiming done.

Primary reference: `CLAUDE.md`.
