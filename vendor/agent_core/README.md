# AgentCore

AgentCore is a Ruby library for building agentic applications.

It provides four cohesive modules with a one-way data flow:

- **Resources**: provider adapter, chat history, memory, tools (native + MCP + skills)
- **PromptBuilder**: prompt assembly pipeline (swappable)
- **PromptRunner**: LLM execution + tool calling loop (pause/resume)
- **Agent**: top-level orchestrator (Builder pattern, serializable config)

AgentCore is a library, not a framework: it does not prescribe persistence,
background jobs, HTTP clients, or UI. The host app wires those pieces in.

## Installation

In this repo, AgentCore is vendored under `vendor/agent_core/`. In a Rails app:

```ruby
# Gemfile
gem "agent_core", path: "vendor/agent_core"
```

## Quick start

```ruby
require "agent_core"

provider = MyProvider.new # implements AgentCore::Resources::Provider::Base#chat

registry = AgentCore::Resources::Tools::Registry.new
registry.register(
  AgentCore::Resources::Tools::Tool.new(
    name: "echo",
    description: "Echo back text",
    parameters: {
      type: "object",
      additionalProperties: false,
      properties: { text: { type: "string" } },
      required: ["text"],
    },
  ) { |args, **| AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text")) }
)

agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.model = "m1"
  b.system_prompt = "You are helpful."
  b.chat_history = AgentCore::Resources::ChatHistory::InMemory.new
  b.tools_registry = registry
  b.tool_policy = AgentCore::Resources::Tools::Policy::AllowAll.new
end

result = agent.chat("hello")
puts result.text
```

## Config (structured v1)

AgentCore agents are serializable. Config is **versioned** and **structured**.

- Export: `agent.to_config`
- Load: `AgentCore::Agent.from_config(config, provider: ..., ...)`
- Select groups: `agent.to_config(only: [...])` / `agent.to_config(except: [...])`

Top-level groups:

- `:identity`
- `:llm`
- `:execution`
- `:token_budget`
- `:context_management`
- `:prompt_injections`

Example:

```ruby
config = agent.to_config

restored =
  AgentCore::Agent.from_config(
    config,
    provider: provider,
    chat_history: MyChatHistoryStore.new,
    conversation_state: MyConversationStateStore.new,
    memory: MyMemoryStore.new,
    tools_registry: registry,
    tool_policy: AgentCore::Resources::Tools::Policy::AllowAll.new,
  )
```

## Context management (sliding window + auto-compaction)

AgentCore treats **chat history** as the append-only transcript, and manages a
separate **conversation state** for running summaries / compaction checkpoints.
This lets the app persist full history however it wants (DB/file), while the
agent can keep prompts within a token budget.

Enable token budgeting by providing both:

- `token_counter` (app-provided tokenizer or heuristic)
- `context_window` (model context size)

When `auto_compact` is enabled (default), the agent will:

- Drop older turns (sliding window) when the prompt would overflow
- Summarize dropped turns into `conversation_state` and inject the summary back
  into the prompt on subsequent turns

```ruby
agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.model = "m1"
  b.system_prompt = "You are helpful."

  b.chat_history = MyChatHistoryStore.new # app decides persistence
  b.conversation_state = MyConversationStateStore.new

  b.token_counter = AgentCore::Resources::TokenCounter::Heuristic.new
  b.context_window = 128_000
  b.reserved_output_tokens = 4_096

  b.auto_compact = true
  b.memory_search_limit = 5
  b.summary_max_output_tokens = 512
end
```

## Prompt injections (OpenClaw + Codex + app-provided)

AgentCore supports an optional **prompt injections** subsystem:

- `system_section`: append ordered sections to the system prompt
- `preamble_message`: insert ordered messages **before** chat history (Codex-like `<user_instructions>`)

Configure sources under `prompt_injections.sources` in config v1.

### OpenClaw-style: inject a file set into `system_prompt`

```ruby
config = agent.to_config
config[:prompt_injections][:sources] = [
  {
    type: "file_set",
    section_header: "Project Context",
    total_max_bytes: 30_000,
    files: [
      { path: "SOUL.md", max_bytes: 10_000, prompt_modes: [:full, :minimal] },
      { path: "MEMORY.md", max_bytes: 10_000, prompt_modes: [:full] },
    ],
  },
]
```

### Codex-style: inject layered `AGENTS.md` into preamble user message

```ruby
config[:prompt_injections][:sources] = [
  {
    type: "repo_docs",
    filenames: ["AGENTS.md"],
    max_total_bytes: 30_000,
    wrapper_template: "<user_instructions>\n{{content}}\n</user_instructions>",
  },
]
```

### App-provided: load items per call (DB, cache, etc.)

Use the `provided` source, and pass items via `ExecutionContext`:

```ruby
agent = AgentCore::Agent.from_config(config, provider: provider)

ctx =
  AgentCore::ExecutionContext.from(
    prompt_mode: :minimal,
    prompt_injections: [
      { target: :preamble_message, role: :user, content: "..." , order: 10 },
      { target: :system_section, content: "..." , order: 300 },
    ],
  )

agent.chat("hi", context: ctx)
```

More details: see `docs/agent_core/prompt_injections.md`.

## Tool calling + pause/resume (confirm)

A tool policy can return `Decision.confirm(...)` to pause the run before any
tool executes. Resume later with user/admin confirmations.

```ruby
policy =
  Class.new(AgentCore::Resources::Tools::Policy::Base) do
    def authorize(name:, arguments: {}, context: {})
      Decision.confirm(reason: "needs approval")
    end
  end.new

agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.model = "m1"
  b.system_prompt = "You can use tools."
  b.tools_registry = registry
  b.tool_policy = policy
end

paused = agent.chat("do something")

if paused.awaiting_tool_confirmation?
  confirmations = { "tc_1" => :allow } # tool_call_id => :allow/:deny (or true/false)
  final = agent.resume(continuation: paused, tool_confirmations: confirmations)
end
```

Notes:

- `continuation:` accepts a `PromptRunner::Continuation` or a `PromptRunner::RunResult`.
- `RunResult.run_id` is stable across `chat` → `resume`.
- For cross-process persistence, serialize continuations with `PromptRunner::ContinuationCodec`.

## Tool execution + pause/resume (defer)

If you want tools to execute asynchronously (ActiveJob, queues, etc.), set the
agent's `tool_executor` to `DeferAll`. The run pauses when tool calls appear,
and the app resumes with externally computed `ToolResult`s.

```ruby
agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.model = "m1"
  b.system_prompt = "You can use tools."
  b.tools_registry = registry
  b.tool_policy = AgentCore::Resources::Tools::Policy::AllowAll.new
  b.tool_executor = AgentCore::PromptRunner::ToolExecutor::DeferAll.new
end

paused = agent.chat("hi")

if paused.awaiting_tool_results?
  tool_results = { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") }
  final = agent.resume_with_tool_results(continuation: paused, tool_results: tool_results)
end
```

## Skills store (recommended wiring)

Register a `Skills::Store` into the tools registry:

```ruby
store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: ["./skills"])
registry.register_skills_store(store)
```

This adds native tools:

- `skills.list`
- `skills.load`
- `skills.read_file`

## MCP tools naming

When registering multiple MCP servers, prefer `server_id:` to get safe, stable
local tool names:

```ruby
registry.register_mcp_client(mcp_client, server_id: "local-fs")
# local tool names: mcp_local-fs__read_file, ...
```

## Streaming

Use `chat_stream` / `resume_stream` / `resume_stream_with_tool_results` to
receive `AgentCore::StreamEvent` objects:

```ruby
agent.chat_stream("hello") do |event|
  case event
  when AgentCore::StreamEvent::TextDelta then print event.text
  end
end
```

## Development

Run gem lint + tests:

```sh
cd vendor/agent_core && bundle exec rake
```
