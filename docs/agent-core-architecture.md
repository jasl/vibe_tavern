# AgentCore Gem — Architecture (Implementation Notes)

> Location: `vendor/agent_core/`
> Status: Implemented
> Updated: 2026-02-15

AgentCore is a Ruby gem that provides the core primitives for building AI agent
applications. It is a **library, not a framework**:

- no database/persistence opinions
- no background job framework coupling
- no HTTP client choice forced (provider adapter boundary)
- no Rails dependency (pure Ruby)

The host application wires in IO, storage, and authorization rules.

## Module overview

```
AgentCore
├── Resources          # Data & adapters: provider, history, memory, tools, skills
├── PromptBuilder      # Prompt assembly pipeline
├── PromptRunner       # LLM execution + tool loop (pause/resume)
└── Agent              # Top-level orchestration (Builder, serializable config)
```

One-way flow (high level):

`Resources` → `PromptBuilder` → `PromptRunner` → `RunResult`

`Agent` is the convenience orchestrator that ties them together.

## Core boundaries

### Provider boundary (LLM API)

The app implements `AgentCore::Resources::Provider::Base`:

- `#chat(messages:, model:, tools: nil, stream: false, **options)`
  - returns `AgentCore::Resources::Provider::Response` when `stream: false`
  - returns an `Enumerator` of `AgentCore::StreamEvent` when `stream: true`

AgentCore ships `AgentCore::Resources::Provider::SimpleInferenceProvider` for
OpenAI-compatible APIs (via the optional `simple_inference` gem).

### ChatHistory boundary (persistence)

AgentCore provides `Resources::ChatHistory::InMemory`. Apps can implement their
own `ChatHistory::Base` for persistence. ChatHistory is treated as the source of
conversation context for prompt building.

### Tools boundary (capabilities)

`Resources::Tools::Registry` unifies:

- native Ruby tools (`Resources::Tools::Tool`)
- MCP tools (`registry.register_mcp_client(...)`)
- skills store tools (`registry.register_skills_store(...)`)

Authorization is handled by `Resources::Tools::Policy::Base`.

Execution strategy is handled by `PromptRunner::ToolExecutor` (Inline/DeferAll/ThreadPool).

## Pause/resume model (two orthogonal mechanisms)

AgentCore supports two independent pause/resume mechanisms:

1) **Authorization pause** (`Decision.confirm(...)`)
   - stop_reason: `:awaiting_tool_confirmation`
   - resume via `resume(...)` with `tool_confirmations`

2) **Execution pause** (`ToolExecutor::DeferAll`)
   - stop_reason: `:awaiting_tool_results`
   - resume via `resume_with_tool_results(...)` with `tool_results`

They compose: a run can pause for confirmation first, then (after approval) pause
again for external execution.

Recommended docs:

- `docs/agent_core/tool_authorization.md`
- `docs/agent_core/tool_execution.md`

## Agent orchestration

`AgentCore::Agent` is built via a Builder DSL and is designed so its config can
round-trip via `#to_config` / `.from_config(...)`.

Important behavior detail:

- `PromptRunner::RunResult.messages` are the **new messages produced by the run**
  (assistant messages and tool_result messages), not the input history and not
  the user message.
- `Agent#chat` appends the user message and then appends `run_result.messages`
  into `chat_history`.

Agent exposes top-level pause/resume entrypoints:

- `Agent#resume` / `Agent#resume_stream`
- `Agent#resume_with_tool_results` / `Agent#resume_stream_with_tool_results`

Apps generally should not need to call `PromptRunner::Runner#resume*` directly
unless they want lower-level control.

## Namespaces (drift notes)

- MCP is implemented under `AgentCore::MCP` (not under `Resources::Tools::*`).
- Skills are implemented under `AgentCore::Resources::Skills`.

## Directory structure (current)

```
vendor/agent_core/lib/agent_core/
├── agent.rb
├── agent/ (builder)
├── execution_context.rb
├── mcp/
├── observability/
├── prompt_builder/
├── prompt_runner/
└── resources/
    ├── chat_history/
    ├── memory/
    ├── provider/
    ├── skills/
    ├── token_counter/
    └── tools/
        ├── policy/
        ├── registry.rb
        ├── tool.rb
        └── tool_result.rb
```
