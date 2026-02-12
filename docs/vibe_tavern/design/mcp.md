# MCP (Model Context Protocol) (stdio MVP)

This repo includes a **stdio transport** MVP implementation of an MCP client and
adapters to expose MCP tools as VibeTavern tool-calling tools.

Scope (MVP):
- JSON-RPC 2.0 over a stateful stdio connection
- lifecycle handshake: `initialize` + `notifications/initialized`
- tool endpoints: `tools/list` (pagination) and `tools/call`

Non-goals (intentionally not implemented here):
- HTTP transport
- OAuth / authorization flows
- `resources/read`, `prompts/get`, or other MCP surfaces beyond tools

## Components

- `Tools::MCP::Transport::Stdio`
  - spawns a subprocess via `Open3.popen3`
  - reads stdout/stderr line-by-line in background threads
  - writes newline-delimited JSON messages to stdin
- `Tools::MCP::JsonRpcClient`
  - manages request ids, pending requests, and timeouts
- `Tools::MCP::Client`
  - performs MCP handshake and exposes `#list_tools` / `#call_tool`

Code:
- `lib/tavern_kit/vibe_tavern/tools/mcp/transport/stdio.rb`
- `lib/tavern_kit/vibe_tavern/tools/mcp/json_rpc_client.rb`
- `lib/tavern_kit/vibe_tavern/tools/mcp/client.rb`

## Tool adaptation

Remote MCP tool definitions are adapted into local OpenAI-compatible tool names:

- local name pattern: `mcp_<server_id>__<remote_tool_name>`
- characters are sanitized to `^[A-Za-z0-9_-]+$`
- maximum length: 128 (stable truncation with hash suffix)

`Tools::MCP::ToolRegistryBuilder` connects to configured servers, paginates
`tools/list`, and returns a `Tools::MCP::Snapshot`:

- `definitions`: `ToolsBuilder::Definition[]` for model exposure
- `mapping`: local name → `{ server_id, remote_tool_name }`
- `clients`: server_id → started `Tools::MCP::Client`
- `close`: closes all clients (and their subprocesses)

Code:
- `lib/tavern_kit/vibe_tavern/tools/mcp/tool_adapter.rb`
- `lib/tavern_kit/vibe_tavern/tools/mcp/tool_registry_builder.rb`

## Tool execution

`ToolCalling::Executors::McpExecutor` routes a local tool call via the mapping
table, calls `tools/call`, and wraps the MCP result into the standard VibeTavern
tool result envelope.

It also builds a best-effort `data[:text]` summary by concatenating MCP text
content blocks and appending `structuredContent` (as JSON) when present.

Tool outputs are size-guarded (default: 200_000 bytes); large/binary payloads
are truncated and warnings are emitted.

Code:
- `lib/tavern_kit/vibe_tavern/tool_calling/executors/mcp_executor.rb`

## Wiring into ToolLoopRunner

MCP tool surfaces are dynamic and often app-owned (process lifecycle, caching,
refresh cadence). The infra layer treats MCP as a tool **snapshot**:

- the app builds an MCP tool snapshot (`Tools::MCP::Snapshot`)
  - `Tools::MCP::ToolRegistryBuilder` is a convenience that can connect to servers and return the snapshot
- the app then assembles the final model-visible tool surface via `TavernKit::VibeTavern::ToolsBuilder`
  - `registry = ToolsBuilder.build(..., mcp_definitions: snapshot.definitions)`
- the app builds a runtime executor via `ToolCalling::ExecutorBuilder`
  - `executor = ToolCalling::ExecutorBuilder.build(..., registry: registry, mcp_snapshot: snapshot, default_executor: ...)`
- pass `registry` and `executor` into `ToolCalling::ToolLoopRunner`
- ensure MCP clients are closed when done via `snapshot.close` (they own subprocesses)
