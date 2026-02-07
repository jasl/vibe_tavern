# Deferred: Agent-driven Character & Lorebook Generation

This repo started with an initial (ambitious) goal: an **agent-driven workflow**
that can help users generate and iteratively edit:

- Character cards (CCv2/CCv3)
- Lore books / world info (SillyTavern / Risu / Character Book variants)

That product-level goal is **deferred** for now. We are currently focusing on
making the **protocol layer** reliable across models/providers:

- Tool use (multi-turn tool loop): `docs/research/vibe_tavern/tool-calling.md`
- Structured directives (single-turn UI/state instructions): `docs/research/vibe_tavern/directives.md`

This document is a parking lot for the original goal: requirements, candidate
architecture ideas, and open questions. Nothing here is “locked in”.

## Why deferred

- Model/provider variance is real (tool calling and structured outputs are not
  uniformly supported).
- Without a stable protocol layer + eval harness, product workflows become
  fragile, model-specific prompt magic.

## Candidate workflow concepts (TBD)

### Workspace / state model (idea)

An editor workflow likely needs an explicit workspace object separate from chat
history, so state is addressable, inspectable, and auditable:

- `facts`: strong facts / authoritative state (should not drift)
- `draft`: editable working state (iterated frequently)
- `locks`: what cannot be changed implicitly
- optional UI state (active panels/forms)

This concept is useful for reasoning about tool surfaces, but the final data
model and persistence approach is still open.

### Facts confirmation (idea)

Facts should not be self-committed by the model. A candidate pattern:

1) model proposes: `facts.propose`
2) app/UI confirms: `facts.commit` (not exposed as a model-facing tool)

Whether this is implemented via tools, directives, or app-level orchestration is
still TBD.

## Tool surface (TBD)

Open questions we intentionally postponed until tool/directives reliability is
proven:

- Minimum tool set for the first editor prototype (import/export later?).
- How to keep tool result envelopes small and stable (avoid context bloat).
- Whether to allow parallel tool calls per turn in production.
- Streaming strategy (if any) for multi-turn tool loops.

## References

- Pipeline / prompt building: `docs/rewrite/vibe-tavern-pipeline.md`
- Rails integration notes: `docs/rewrite/rails-integration-guide.md`
- Tool calling work plan: `docs/rewrite/tool-calling-work-plan.md`
