# Phase 2 — Completion Report

> Date: 2026-02-14
> Status: ✅ Complete
> Tests: 575 runs, 1112 assertions, 0 failures, 0 errors

## What Was Delivered

Phase 2 adds MCP (Model Context Protocol) and Skills modules, plus a
comprehensive test coverage expansion across Phase 1 + 2.

### New Source Files (16 source)

```
# MCP — Model Context Protocol (10 files)
lib/agent_core/mcp.rb                                  # Namespace loader (requires all MCP modules)
lib/agent_core/mcp/constants.rb                        # Protocol version, JSON-RPC error codes
lib/agent_core/mcp/json_rpc_client.rb                  # JSON-RPC 2.0 request/response/notification client
lib/agent_core/mcp/client.rb                           # High-level MCP client (initialize, list_tools, call_tool)
lib/agent_core/mcp/server_config.rb                    # ServerConfig Data.define (command, args, env, url, headers)
lib/agent_core/mcp/sse_parser.rb                       # SSE (Server-Sent Events) incremental parser
lib/agent_core/mcp/tool_adapter.rb                     # MCP tool name mapping helpers (local name builder)
lib/agent_core/mcp/transport/base.rb                   # Abstract transport (send_message, receive, close)
lib/agent_core/mcp/transport/stdio.rb                  # Stdio transport (stdin/stdout JSON-RPC)
lib/agent_core/mcp/transport/streamable_http.rb        # Streamable HTTP transport (httpx, optional dep)

# Skills — Markdown-based agent capabilities (5 files)
lib/agent_core/resources/skills/skill_metadata.rb      # SkillMetadata Data.define (name, description, location, ...)
lib/agent_core/resources/skills/skill.rb               # Skill Data.define (meta, body_markdown, files_index)
lib/agent_core/resources/skills/frontmatter.rb         # YAML frontmatter parser with strict/lenient modes
lib/agent_core/resources/skills/store.rb               # Abstract Store (list_skills, load_skill, read_skill_file)
lib/agent_core/resources/skills/file_system_store.rb   # Filesystem-backed Store with security (realpath, traversal)
```

### Modified Source Files (3 files)

```
lib/agent_core.rb              # Added require paths for MCP + Skills
lib/agent_core/errors.rb       # Added MCP::ClosedError, ProtocolVersionNotSupportedError, JsonRpcError
lib/agent_core/utils.rb        # Added assert_symbol_keys! for API boundary enforcement
```

### New Test Files (23 test files)

```
# MCP tests (9 files)
test/agent_core/mcp/constants_test.rb
test/agent_core/mcp/server_config_test.rb
test/agent_core/mcp/json_rpc_client_test.rb
test/agent_core/mcp/client_test.rb
test/agent_core/mcp/sse_parser_test.rb
test/agent_core/mcp/tool_adapter_test.rb
test/agent_core/mcp/transport/base_test.rb
test/agent_core/mcp/transport/stdio_test.rb
test/agent_core/mcp/transport/streamable_http_test.rb

# Skills tests (5 files)
test/agent_core/resources/skills/store_test.rb
test/agent_core/resources/skills/skill_test.rb
test/agent_core/resources/skills/skill_metadata_test.rb
test/agent_core/resources/skills/frontmatter_test.rb
test/agent_core/resources/skills/file_system_store_test.rb

# Coverage expansion tests — Phase 1 classes that lacked dedicated tests (9 files)
test/agent_core/errors_test.rb
test/agent_core/stream_event_test.rb
test/agent_core/configuration_test.rb
test/agent_core/prompt_runner/events_test.rb
test/agent_core/prompt_runner/run_result_test.rb
test/agent_core/resources/provider/response_test.rb
test/agent_core/resources/provider/base_test.rb
test/agent_core/resources/tools/tool_test.rb
test/agent_core/resources/tools/tool_result_test.rb
```

### Modified Test Files (3 files)

```
test/test_helper.rb                            # SimpleCov config: primary_coverage :line, exclude streamable_http
test/agent_core/message_test.rb                # Expanded ~97 → ~640 lines (ContentBlock, media types, roundtrips)
test/agent_core/resources/tools/registry_test.rb  # Removed duplicate ToolTest/ToolResultTest classes
```

### Test Fixtures

```
test/fixtures/skills/example-skill/SKILL.md
test/fixtures/skills/another-skill/SKILL.md
test/fixtures/skills/another-skill/scripts/setup.sh
test/fixtures/skills/another-skill/references/guide.md
test/fixtures/skills/another-skill/assets/logo.txt
```

## Plan Compliance Checklist

| Plan Item | Status | Notes |
|-----------|--------|-------|
| MCP Constants (protocol version, error codes) | ✅ | |
| MCP ServerConfig (Data.define) | ✅ | |
| MCP Transport::Base (abstract) | ✅ | |
| MCP Transport::Stdio | ✅ | |
| MCP Transport::StreamableHttp | ✅ | Optional dep (httpx), not auto-required |
| MCP SseParser | ✅ | |
| MCP JsonRpcClient (request/notify) | ✅ | |
| MCP Client (initialize/list_tools/call_tool) | ✅ | |
| MCP ToolAdapter (tool name mapping) | ✅ | |
| Skills SkillMetadata (Data.define) | ✅ | |
| Skills Skill (Data.define) | ✅ | |
| Skills Frontmatter parser | ✅ | Strict + lenient modes |
| Skills Store (abstract) | ✅ | |
| Skills FileSystemStore | ✅ | Security: realpath, traversal checks |
| Skills under Resources namespace | ✅ | Refactored from AgentCore::Skills to AgentCore::Resources::Skills |
| Tests for all of the above | ✅ | 578 tests |
| Coverage expansion for Phase 1 gaps | ✅ | 12 new/expanded test files |

## Architecture Notes

### MCP Module Structure

```
AgentCore::MCP
  ├── Constants           # Protocol version, JSON-RPC codes
  ├── ServerConfig        # Immutable config (Data.define)
  ├── JsonRpcClient       # JSON-RPC 2.0 protocol layer
  ├── Client              # High-level: initialize → list_tools → call_tool
  ├── SseParser           # SSE stream parsing
  ├── ToolAdapter         # MCP tool → AgentCore Tool conversion
  └── Transport
      ├── Base            # Abstract (send_message, receive, close)
      ├── Stdio           # stdin/stdout (subprocess)
      └── StreamableHttp  # HTTP+SSE (optional httpx dependency)
```

### Skills Module Structure (under Resources)

```
AgentCore::Resources::Skills
  ├── SkillMetadata       # Immutable metadata (Data.define)
  ├── Skill               # Full skill: metadata + body + files_index (Data.define)
  ├── Frontmatter         # YAML frontmatter parser (module_function)
  ├── Store               # Abstract base class
  └── FileSystemStore     # Filesystem-backed implementation
```

### Dependency Direction

```
Agent ──→ PromptBuilder ──→ Resources (ChatHistory, Memory, Tools, Skills)
  │                            ↑
  └──→ PromptRunner ───────────┘
  │
  └──→ MCP (Client → JsonRpcClient → Transport)
```

MCP is an independent leaf module (pure JSON-RPC + transports). Skills lives under
`Resources::Skills` but does not depend on Tools.

## What Was Deferred

- `Registry#register_skill` — connecting Skills to the tool registry
- File system watcher for live skill reload
- Full MCP session reconnection/backoff strategy (beyond one-shot reinitialize on session-not-found)
- StreamableHttp integration tests (requires httpx)
