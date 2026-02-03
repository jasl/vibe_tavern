# Tool Calling Design (Rails rewrite PoC)

This document records the current decisions and the planned implementation for
LLM tool calling in the Rails rewrite.

Scope:
- app-owned orchestration (`tool call -> execute -> tool output -> continue`)
- multi-provider support (start OpenAI-compatible; keep extension points)
- evaluation harness (offline + optional live via OpenRouter)

Non-goals (for now):
- UI implementation
- full CCv3 editor/exporter product logic

## Decisions (Locked In)

These are the current source-of-truth decisions for the PoC and early product
architecture.

### 1) Workspace/State model: **B**

- We will model editing state as an explicit **EditorWorkspace/Project** concept
  (separate from chat history).
- The workspace holds:
  - `facts` (strong facts / authoritative state)
  - `draft` (editable working state)
  - `locks` (what cannot be changed implicitly)
  - optional UI state (which panels/forms are active)

Rationale:
- The editor is not a linear “chat only” session; state must be addressable,
  inspectable, and auditable independent of message history.

### 2) Facts commit requires user confirmation: **A**

- The model must not self-commit facts.
- Facts changes are two-step:
  1) `facts.propose` (agent suggests)
  2) `facts.commit` (only after explicit user/UI confirmation)
- `facts.commit` is **not exposed to the model** in the model-facing tool list.

Rationale:
- Facts are “strong truth” and must not drift due to model hallucination.

### 3) Provider/API support

- Start with **OpenAI-compatible** tool calling for the first implementation and
  live testing (OpenRouter).
- The code structure must keep extension points for non-OpenAI API shapes
  (Anthropic/Claude tool_use, Gemini function calling, etc.).

Rationale:
- OpenAI-compatible endpoints cover many providers/models and are the fastest
  way to validate robustness; but we must not bake in OpenAI-only assumptions.

### 4) Prompt Plan must carry tool definitions

- Tool definitions and request options must be included in `Prompt::Plan` via
  `plan.llm_options` (for caching/auditing/fingerprints).

Rationale:
- Tools materially change the effective prompt contract and must be part of the
  plan’s “request surface” for reproducibility.

## Implementation Sketch (PoC)

### Components

1) `ToolRegistry`
   - allowlist of tools + JSON schema (keep schemas simple and cross-provider)

2) `ToolDispatcher`
   - validates tool name + args
   - executes tool
   - returns a normalized envelope `{ ok, data, warnings, errors }`

3) `ToolLoopRunner`
   - builds prompt via `TavernKit::VibeTavern` (dialect: `:openai`)
   - sends `messages + llm_options(tools, tool_choice, ...)` via `SimpleInference`
   - parses `tool_calls`
   - executes tools, appends tool result messages, loops until final assistant
   - emits a trace (for debugging / replay / tests)

### State: in-memory first

For early tool-loop correctness and evaluation, we will implement an in-memory
workspace store (no DB). The API shape should match the future DB-backed
implementation so we can swap storage later.

## Evaluation Harness

### Offline (default in CI)

- Deterministic fake provider responses that:
  - request tools
  - test invalid args / unknown tool failures
  - test multi-step loops and termination conditions

Purpose:
- lock in tool-loop behavior without network flakiness.

### Optional live (OpenRouter)

- A separate runner that can test multiple models via OpenRouter (OpenAI
  compatible).
- Gate behind env vars (e.g., `OPENROUTER_API_KEY`, `OPENROUTER_MODEL=...`) so
  CI stays deterministic.

Purpose:
- detect model-specific quirks in tool calling and JSON argument quality.

Script:

```sh
# Single model
OPENROUTER_API_KEY=... OPENROUTER_MODEL="openai/gpt-4.1-mini" \
  bundle exec ruby script/llm_tool_call_eval.rb

# Multiple models
OPENROUTER_API_KEY=... OPENROUTER_MODELS="openai/gpt-4.1-mini,anthropic/claude-3.5-sonnet" \
  bundle exec ruby script/llm_tool_call_eval.rb
```

## Open Questions (Parking Lot)

These are intentionally deferred until we have the PoC loop + tests.

- Do we want to support parallel tool calls in a single turn?
- Do we want streaming for tool-call runs, or keep PoC non-streaming only?
- How do we standardize tool result envelopes across providers (and keep them
  small to avoid context bloat)?
- What is the minimum set of tools for the first editor prototype
  (CCv3-only, import/export later)?
