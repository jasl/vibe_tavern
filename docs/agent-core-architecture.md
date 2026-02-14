# AgentCore Gem — Architecture Design

> Location: `vendor/agent_core/`
> Status: Design phase → Implementation
> Date: 2026-02-14

## 1. Vision

AgentCore is a Ruby gem that provides the core primitives for building AI agent
applications. It is a **library, not a framework** — it handles no IO/network
directly, exposing interfaces for the host application to implement.

Design principles:
- **First-principles primitives** that compose into complex behavior
- **Serializable agents** via Builder pattern (persona/prompt configs saveable)
- **Pluggable prompt pipeline** (swappable implementations)
- **Concurrency-friendly** (thread-safe, Fiber-compatible)
- **No IO in the gem** — app provides adapters for LLM API, persistence, etc.

## 2. Module Overview

```
AgentCore
├── Resources          # Data layer: connections, history, memory, tools
├── PromptBuilder      # Prompt assembly pipeline
├── PromptRunner       # LLM execution + tool calling loop
└── Agent              # Top-level orchestrator (Builder pattern)
```

## 3. Module Details

### 3.1 Resources

Manages all data the agent needs. Defines abstract contracts; app implements.

#### 3.1.1 Provider (LLM Connection)

```ruby
AgentCore::Resources::Provider
  # Abstract: the app implements this
  # - #chat(messages:, model:, tools:, stream:, **options) → Response | Enumerator
  # - #models → Array<ModelInfo>
  # - #name → String
```

The gem ships a `Provider::Base` with the contract. The app wraps its HTTP
client (e.g., ruby_llm, faraday, httpx) into a Provider subclass.

**Response** is a Data class:
```ruby
AgentCore::Resources::Response
  # message: Message (assistant)
  # tool_calls: Array<ToolCall>
  # usage: Usage (input_tokens, output_tokens)
  # raw: Hash (provider-specific)
  # stop_reason: Symbol (:end_turn, :tool_use, :max_tokens, :stop_sequence)
```

**Streaming**: Provider#chat with `stream: true` returns an Enumerator that
yields `StreamEvent` objects (text_delta, tool_call_delta, thinking_delta, done).

#### 3.1.2 ChatHistory

```ruby
AgentCore::Resources::ChatHistory::Base   # Abstract Enumerable
  # #append(message) → self
  # #each { |msg| } → Enumerator
  # #size → Integer
  # #clear → self
  # #last(n) → Array<Message>
  # #to_a → Array<Message>

AgentCore::Resources::ChatHistory::InMemory  # Built-in array-backed impl
```

Ported from `vendor/tavern_kit/lib/tavern_kit/chat_history.rb`.

#### 3.1.3 Memory

```ruby
AgentCore::Resources::Memory::Base  # Abstract
  # #search(query:, limit:) → Array<MemoryEntry>
  # #store(content:, metadata:) → MemoryEntry
  # #forget(id:) → Boolean
```

The gem provides the contract; app implements with pgvector, sqlite-vec, etc.
In-memory implementation included for testing.

#### 3.1.4 Tools (Unified Registry)

Three tool sources unified under one registry:

```ruby
AgentCore::Resources::Tools::Registry
  # #register(tool) → self
  # #register_mcp_server(config) → self
  # #register_skill(skill) → self
  # #definitions(expose: :model) → Array<ToolDefinition>
  # #find(name) → Tool | nil
  # #execute(name:, arguments:, context:) → ToolResult

AgentCore::Resources::Tools::Tool  # Native tool
  # name, description, parameters (JSON Schema), #call(arguments, context:)

AgentCore::Resources::Tools::ToolResult
  # content: Array<ContentBlock>  (text, image, etc.)
  # error: Boolean
  # metadata: Hash
```

**MCP Integration** — ported from `lib/tavern_kit/vibe_tavern/tools/mcp/`:

```ruby
AgentCore::Resources::Tools::MCP::Client
  # Wraps JSON-RPC 2.0 communication
  # Transport is injected (StdIO, StreamableHTTP, or custom)
  # #initialize → negotiates capabilities
  # #list_tools → Array<ToolDefinition>
  # #call_tool(name:, arguments:) → ToolResult

AgentCore::Resources::Tools::MCP::Transport::Base    # Abstract
AgentCore::Resources::Tools::MCP::Transport::StdIO
AgentCore::Resources::Tools::MCP::Transport::StreamableHTTP
```

**Skills** — simplified from `lib/tavern_kit/vibe_tavern/tools/skills/`:

```ruby
AgentCore::Resources::Tools::Skills::Store  # Abstract
  # #list → Array<SkillMetadata>
  # #load(name:) → Skill
  # #read_file(name:, path:) → String

AgentCore::Resources::Tools::Skills::FileSystemStore  # Built-in
```

**Tool Policy** — ported from existing:

```ruby
AgentCore::Resources::Tools::Policy::Base  # Abstract
  # #filter(tools:, context:) → Array<ToolDefinition>
  # #authorize(name:, arguments:, context:) → Decision

AgentCore::Resources::Tools::Policy::Decision
  # allowed?, denied?, requires_confirmation?
  # reason: String
```

### 3.2 PromptBuilder

Assembles the final prompt from resources, templates, and user input.
The pipeline is an interface — can be swapped for simple or complex workflows.

```ruby
AgentCore::PromptBuilder::Pipeline  # Abstract
  # #build(context:) → BuiltPrompt

AgentCore::PromptBuilder::BuiltPrompt
  # system_prompt: String
  # messages: Array<Message>
  # tools: Array<ToolDefinition>
  # options: Hash (temperature, max_tokens, etc.)

AgentCore::PromptBuilder::SimplePipeline  # Built-in default
  # Direct assembly: system_prompt + history + tools
  # No macro expansion, no injection planning

AgentCore::PromptBuilder::Context
  # Bag of data available to the pipeline:
  # - system_prompt_template: String
  # - chat_history: ChatHistory
  # - tools_registry: Tools::Registry
  # - memory_results: Array<MemoryEntry> (optional)
  # - user_message: String
  # - variables: Hash
  # - agent_config: Hash (serialized agent settings)
```

Future: a `TemplatePipeline` that supports Liquid/ERB macros, injection
planning, context templates — for ST-style complex workflows.

### 3.3 PromptRunner

Sends the built prompt to the LLM and handles the tool-calling loop.

```ruby
AgentCore::PromptRunner::Runner
  # #run(prompt:, provider:, tools_registry:, **options) → RunResult
  # #run_stream(prompt:, provider:, tools_registry:, **options) { |event| } → RunResult
  #
  # Internally:
  # 1. Send prompt to provider
  # 2. If response has tool_calls → execute tools → append results → loop
  # 3. If response is final text → return
  # 4. Respect max_turns, handle errors, emit events

AgentCore::PromptRunner::RunResult
  # messages: Array<Message>  (full conversation from this run)
  # final_message: Message    (last assistant message)
  # turns: Integer
  # usage: AggregatedUsage
  # tool_calls_made: Array<ToolCallRecord>

AgentCore::PromptRunner::Events
  # Callback-based event system:
  # - on_turn_start { |turn_number| }
  # - on_llm_request { |messages, tools| }
  # - on_llm_response { |response| }
  # - on_tool_call { |name, arguments, tool_call_id| }
  # - on_tool_result { |name, result, tool_call_id| }
  # - on_turn_end { |turn_number, messages| }
  # - on_stream_delta { |delta| }  (for streaming mode)
  # - on_error { |error, recoverable?| }
```

**Streaming architecture**: The runner calls `provider.chat(stream: true)`,
iterates the enumerator, forwards incremental deltas (text/tool calls), and
captures `MessageComplete` + the provider `Done` internally to build the turn
result. If the assistant requests tool calls, it executes tools, appends tool
results, and loops. Each LLM call yields a `TurnEnd` (including stop_reason +
usage for that turn), and the runner emits a single `Done` event when the whole
run completes.

**Concurrency considerations**:
- Tool execution is sequential by default (one at a time, like pi-mono)
- MCP calls may use threads internally (JsonRpcClient uses Mutex + ConditionVariable)
- StreamableHTTP transport uses Fiber-compatible IO where possible
- The runner itself is re-entrant: no shared mutable state

### 3.4 Agent (Top-level)

The Agent is the public-facing object. Built via Builder, serializable.

```ruby
agent = AgentCore::Agent.build do |b|
  # Identity (serializable)
  b.name = "Assistant"
  b.system_prompt = "You are a helpful assistant..."
  b.description = "General-purpose agent"

  # Model preferences (serializable)
  b.model = "claude-sonnet-4-5-20250929"
  b.temperature = 0.7
  b.max_tokens = 4096

  # Resources (runtime, not serialized)
  b.provider = MyAppProvider.new(api_key: ENV["ANTHROPIC_API_KEY"])
  b.chat_history = AgentCore::Resources::ChatHistory::InMemory.new
  b.memory = MyPgvectorMemory.new
  b.tools_registry = build_tools_registry()

  # Pipeline (pluggable)
  b.prompt_pipeline = AgentCore::PromptBuilder::SimplePipeline.new

  # Runner options
  b.max_turns = 10
  b.on_event = method(:handle_agent_event)
end

# Serialization (identity + model prefs only)
config = agent.to_config  # => Hash (JSON-serializable)
AgentCore::Agent.from_config(config, provider: ..., history: ...)

# Execution
result = agent.chat("Hello!")
agent.chat_stream("Hello!") { |event| ... }
```

**Agent#chat flow**:
1. Append user message to chat_history
2. Optionally query memory for relevant context
3. Build prompt via pipeline (system + history + tools + memory)
4. Run prompt via PromptRunner (handles tool loop)
5. Append assistant messages to chat_history
6. Return result

## 4. Message Format

Unified message format used throughout:

```ruby
AgentCore::Message
  # role: :system | :user | :assistant | :tool_result
  # content: String | Array<ContentBlock>
  # tool_calls: Array<ToolCall> (for assistant messages)
  # tool_call_id: String (for tool_result messages)
  # name: String (optional, for tool_result)
  # metadata: Hash (timestamps, token counts, etc.)

AgentCore::ContentBlock  # Union type
  # TextContent:   { type: :text, text: String }
  # ImageContent:  { type: :image, source: Hash }
  # ToolUseContent: { type: :tool_use, id: String, name: String, input: Hash }
  # ToolResultContent: { type: :tool_result, tool_use_id: String, content: String }

AgentCore::ToolCall
  # id: String
  # name: String
  # arguments: Hash

AgentCore::StreamEvent
  # type: :text_delta | :tool_call_start | :tool_call_delta |
  #       :thinking_delta | :done | :error
  # data: Hash (type-specific payload)
```

## 5. Directory Structure

```
vendor/agent_core/
├── lib/
│   ├── agent_core.rb                    # Top-level require
│   ├── agent_core/
│   │   ├── version.rb
│   │   ├── errors.rb
│   │   ├── message.rb                   # Message, ContentBlock, ToolCall
│   │   ├── stream_event.rb
│   │   ├── agent.rb                     # Agent + Builder
│   │   ├── agent/
│   │   │   ├── builder.rb
│   │   │   └── config.rb               # Serialization
│   │   ├── resources/
│   │   │   ├── provider/
│   │   │   │   ├── base.rb
│   │   │   │   └── response.rb
│   │   │   ├── chat_history/
│   │   │   │   ├── base.rb
│   │   │   │   └── in_memory.rb
│   │   │   ├── memory/
│   │   │   │   ├── base.rb
│   │   │   │   └── in_memory.rb
│   │   │   └── tools/
│   │   │       ├── registry.rb
│   │   │       ├── tool.rb
│   │   │       ├── tool_result.rb
│   │   │       ├── mcp/
│   │   │       │   ├── client.rb
│   │   │       │   ├── json_rpc_client.rb
│   │   │       │   ├── transport/
│   │   │       │   │   ├── base.rb
│   │   │       │   │   ├── stdio.rb
│   │   │       │   │   └── streamable_http.rb
│   │   │       │   └── errors.rb
│   │   │       ├── skills/
│   │   │       │   ├── store.rb
│   │   │       │   └── file_system_store.rb
│   │   │       └── policy/
│   │   │           ├── base.rb
│   │   │           └── decision.rb
│   │   ├── prompt_builder/
│   │   │   ├── pipeline.rb             # Abstract
│   │   │   ├── simple_pipeline.rb      # Default impl
│   │   │   ├── built_prompt.rb
│   │   │   └── context.rb
│   │   └── prompt_runner/
│   │       ├── runner.rb
│   │       ├── run_result.rb
│   │       └── events.rb
├── test/
│   ├── test_helper.rb
│   ├── agent_core/
│   │   ├── agent_test.rb
│   │   ├── message_test.rb
│   │   ├── resources/
│   │   │   ├── chat_history_test.rb
│   │   │   ├── memory_test.rb
│   │   │   └── tools/
│   │   │       ├── registry_test.rb
│   │   │       ├── mcp/
│   │   │       │   ├── client_test.rb
│   │   │       │   └── json_rpc_client_test.rb
│   │   │       └── policy_test.rb
│   │   ├── prompt_builder/
│   │   │   └── simple_pipeline_test.rb
│   │   └── prompt_runner/
│   │       └── runner_test.rb
├── agent_core.gemspec
├── Gemfile
├── Rakefile
└── README.md
```

## 6. Implementation Plan (Phases)

### Phase 1: Foundation + Resources (this session)
1. Set up gem structure, gemspec, Rakefile, test_helper
2. Implement Message, ContentBlock, ToolCall, StreamEvent
3. Implement ChatHistory (Base + InMemory)
4. Implement Memory (Base + InMemory)
5. Implement Provider (Base + Response)
6. Implement Tool, ToolResult, ToolDefinition
7. Implement Tools::Registry
8. Tests for all of the above

### Phase 2: Tools Infrastructure
1. Port MCP Client (JsonRpcClient, Transport::Base, StdIO)
2. Port StreamableHTTP transport
3. Port Skills (Store, FileSystemStore)
4. Implement Tool Policy (Base, Decision)
5. Tests for MCP, Skills, Policy

### Phase 3: Prompt Builder
1. Implement Context
2. Implement BuiltPrompt
3. Implement Pipeline (abstract)
4. Implement SimplePipeline
5. Tests

### Phase 4: Prompt Runner
1. Implement Events system
2. Implement Runner (sync mode)
3. Implement Runner (streaming mode)
4. Implement tool-calling loop
5. Implement RunResult
6. Integration tests with mock provider

### Phase 5: Agent
1. Implement Builder
2. Implement Agent (chat, chat_stream)
3. Implement Config serialization
4. End-to-end integration tests

### Phase 6: Rails Integration
1. Create app-level Provider (wrapping ruby_llm or direct HTTP)
2. Wire AgentCore into Rails controllers
3. Replace lib/tavern_kit usage
4. Verify existing tests pass

### Phase 7: Chat UI
1. Build Hotwire-based chat interface
2. Turbo Streams for real-time message streaming
3. Stimulus controllers for input, history, settings
4. Similar to pi-mono web-ui but with Rails conventions

## 7. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Message format | Anthropic-style (content blocks) | Most expressive, easy to convert to OpenAI format |
| Tool execution | Sequential (not parallel) | Simpler, safer, matches pi-mono pattern |
| Streaming | Enumerator-based + callback | Ruby-idiomatic, composable |
| Serialization | JSON-compatible Hash | Maximum portability |
| Error handling | Result objects for expected, exceptions for unexpected | Matches existing app pattern |
| Concurrency | Thread-safe via Mutex, Fiber-compatible | Match MCP transport needs |
| Testing | Minitest + fixtures | Match app conventions |

## 8. What We Drop (For Now)

- SillyTavern pipeline/context_template/injector (future: TemplatePipeline)
- RisuAI support
- Character card ingest (stays in TavernKit)
- Liquid macro expansion (future: TemplatePipeline)
- Output tags system
- Language policy (ST-specific)
- Directives system (can be re-added as a specialized runner)

All dropped features remain achievable by implementing custom Pipeline or
Runner subclasses on top of AgentCore.

## 9. Dependencies

The gem should have **minimal dependencies**:
- `json` (stdlib)
- `uri` (stdlib)
- `net/http` (stdlib, for StreamableHTTP transport)
- `mutex_m` (stdlib, for thread safety)

Optional/dev dependencies:
- `minitest` (testing)
- `rubocop` (linting)
- `rake` (tasks)

No external gems required in the core. The app brings its own HTTP client,
database adapter, etc.
