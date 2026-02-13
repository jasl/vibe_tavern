# MCP (Model Context Protocol)

This repo includes an MCP client and adapters to expose MCP tools as VibeTavern
tool-calling tools.

Supported transports:
- `:stdio` (subprocess + JSON-RPC over stdin/stdout)
- `:streamable_http` (remote Streamable HTTP + JSON-RPC over HTTP)

Scope:
- JSON-RPC 2.0
- lifecycle handshake: `initialize` + `notifications/initialized`
- tools: `tools/list` (pagination) and `tools/call`
- Streamable HTTP response handling:
  - `application/json` one-shot JSON-RPC response
  - `text/event-stream` per-request SSE responses, including disconnect + resume
    via `GET` + `Last-Event-ID` (poll-style reconnect) and `retry:` delays

Non-goals (intentionally not implemented here):
- deprecated “pure SSE transport” (this code only parses SSE as part of Streamable HTTP responses)
- OAuth / authorization flows
- `resources/read`, `prompts/get`, or other MCP surfaces beyond tools

## Configuration

`Tools::MCP::ServerConfig` supports an explicit `transport:`:

- `transport: :stdio`
  - requires: `command:` (+ optional `args/env/chdir`)
  - optional hooks: `on_stderr_line`, `on_stdout_line` (see notes below)
  - optional auth injection: `env_provider` (see notes below)
  - rejects: HTTP-only fields (`url/headers/headers_provider/open_timeout_s/read_timeout_s/sse_max_reconnects/max_response_bytes`)
- `transport: :streamable_http`
  - requires: `url:`
  - optional: `headers:` (for `Authorization`, etc.), `headers_provider`, `open_timeout_s`, `read_timeout_s`, `sse_max_reconnects`, `max_response_bytes`
  - optional hooks: `on_stderr_line`, `on_stdout_line` (see notes below)
  - rejects: stdio-only fields (`command/args/env/env_provider/chdir`)

Defaults:
- `protocol_version`: `Tools::MCP::DEFAULT_PROTOCOL_VERSION` (currently `2025-11-25`)
- supported protocol versions: `Tools::MCP::SUPPORTED_PROTOCOL_VERSIONS`
- `timeout_s`: `Tools::MCP::DEFAULT_TIMEOUT_S`
- `max_response_bytes` (streamable_http only): 8 MB (applies to JSON bodies and per-event SSE `data`)

Notes:
- `headers:` often contains secrets (e.g. `Authorization`); avoid logging.
- `headers_provider:` is called for each outgoing request to compute extra headers (for example: short-lived bearer tokens).
- the server-assigned `MCP-Session-Id` is treated as sensitive; the transport does not emit it in diagnostics.
- if a response exceeds limits, the transport returns JSON-RPC errors (e.g. `HTTP_BODY_TOO_LARGE`, `SSE_EVENT_DATA_TOO_LARGE`, `INVALID_SSE_EVENT_DATA`).
- `on_stdout_line:` receives JSON-RPC message lines (incoming responses/notifications). This can contain sensitive data; avoid logging raw output.
- `on_stderr_line:` is for transport diagnostics (and stdio subprocess stderr). Treat as untrusted and potentially sensitive.

## Examples

STDIO:

```ruby
TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
  id: "local",
  transport: :stdio,
  command: "my-mcp-server",
  args: ["--stdio"],
)
```

Streamable HTTP:

```ruby
TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
  id: "remote",
  transport: :streamable_http,
  url: "https://mcp.example.com/mcp",
  headers: { "Authorization" => "Bearer ..." },
  timeout_s: 30.0,
  open_timeout_s: 5.0,
  read_timeout_s: 30.0,
  sse_max_reconnects: 20,
)
```

## Auth injection hooks

TavernKit does not implement OAuth flows. Instead, it exposes hooks so the host
application can inject credentials at runtime.

Streamable HTTP:

```ruby
TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
  id: "remote",
  transport: :streamable_http,
  url: "https://mcp.example.com/mcp",
  headers_provider: -> { { "Authorization" => "Bearer #{token_store.fetch!}" } },
  on_stderr_line: ->(line) { Rails.logger.debug(line) },
)
```

STDIO:

```ruby
TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
  id: "local",
  transport: :stdio,
  command: "my-mcp-server",
  env_provider: -> { { "MCP_TOKEN" => token_store.fetch! } },
  on_stderr_line: ->(line) { Rails.logger.debug(line) },
)
```

## SaaS host TODO (multi-tenant)

This library focuses on protocol correctness and safe defaults. A production
multi-tenant host must additionally implement:

- Connection/session isolation: key MCP clients by `tenant_id + user_id + server_id + auth_context`, never share sessions across tenants/users.
- Session lifecycle: idle TTL, logout invalidation, token rotation handling, and policy version changes that force session rebuild.
- SSRF controls (when server URLs / discovery URLs are user-configurable): HTTPS enforcement, redirect restrictions, private-network blocking, egress proxying, and DNS rebinding mitigations.
- Secrets management: centralized storage/rotation, least-privilege access, and strict redaction so secrets never enter prompts or logs.
- Audit logs: append-only/WORM storage, retention policy, log-injection hardening, and decision logging for allow/deny/confirm tool policies.

## Components

- `Tools::MCP::Transport::Stdio`
  - spawns a subprocess via `Open3.popen3`
  - reads stdout/stderr line-by-line in background threads
  - writes newline-delimited JSON messages to stdin
  - if the subprocess exits unexpectedly, pending requests fail immediately (no timeout wait)
- `Tools::MCP::Transport::StreamableHttp`
  - sends one JSON-RPC message per HTTP `POST` (requests and notifications)
  - stores server-assigned session id (`MCP-Session-Id`) from the `initialize` response
  - after `initialize`, includes `MCP-Protocol-Version` (negotiated) and `MCP-Session-Id` (if present) on subsequent requests
  - handles `text/event-stream` responses for a request, including disconnect + resume via `GET` + `Last-Event-ID`
  - maps HTTP `404` (when a session id is present) to JSON-RPC error code `MCP_SESSION_NOT_FOUND`
  - supports best-effort cancellation (`notifications/cancelled`) when the JSON-RPC client times out
  - `#close` ensures the worker thread is terminated (kills as a last resort)
- `Tools::MCP::SseParser`
  - incremental SSE parser used by `StreamableHttp` for per-request SSE responses
- `Tools::MCP::JsonRpcClient`
  - manages request ids, pending requests, and timeouts
  - supports per-request timeout overrides via `#request(..., timeout_s: ...)`
- `Tools::MCP::Client`
  - performs MCP handshake and exposes `#list_tools` / `#call_tool`
  - rejects unsupported negotiated protocol versions (fails fast on `start`)
  - supports per-request timeouts via `timeout_s:` on `#list_tools` / `#call_tool`
  - on `MCP_SESSION_NOT_FOUND`:
    - `#list_tools`: re-initializes and retries once (idempotent)
    - `#call_tool`: re-initializes for future calls, but does not auto-retry (avoid repeating side effects)

Code:
- `lib/tavern_kit/vibe_tavern/tools/mcp/transport/stdio.rb`
- `lib/tavern_kit/vibe_tavern/tools/mcp/transport/streamable_http.rb`
- `lib/tavern_kit/vibe_tavern/tools/mcp/sse_parser.rb`
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
- `close`: closes all clients (stdio subprocesses and HTTP sessions)

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
- ensure MCP clients are closed when done via `snapshot.close` (they may own subprocesses and HTTP sessions)
