# Phase 1 — Completion Report

> Date: 2026-02-14
> Status: ✅ Complete (with issues to address)
> Tests: 83 runs, 172 assertions, 0 failures, 0 errors

## What Was Delivered

### Files (24 source + 8 test)

```
lib/agent_core.rb                              # Top-level require, convenience build
lib/agent_core/version.rb                      # 0.1.0
lib/agent_core/errors.rb                       # Error hierarchy
lib/agent_core/message.rb                      # Message, ToolCall, ContentBlock, 4 content types
lib/agent_core/stream_event.rb                 # 13 event classes in StreamEvent module
lib/agent_core/resources/provider/base.rb      # Abstract LLM provider
lib/agent_core/resources/provider/response.rb  # Response + Usage
lib/agent_core/resources/chat_history/base.rb  # Abstract Enumerable history
lib/agent_core/resources/chat_history/in_memory.rb  # Thread-safe array-backed
lib/agent_core/resources/memory/base.rb        # Abstract memory (RAG)
lib/agent_core/resources/memory/in_memory.rb   # Naive substring matching
lib/agent_core/resources/tools/tool.rb         # Native tool definition + execution
lib/agent_core/resources/tools/tool_result.rb  # Unified tool result
lib/agent_core/resources/tools/registry.rb     # Unified tool registry (native + MCP)
lib/agent_core/resources/tools/policy/base.rb  # Abstract policy + Decision
lib/agent_core/prompt_builder/context.rb       # Data bag for pipeline
lib/agent_core/prompt_builder/built_prompt.rb  # Pipeline output
lib/agent_core/prompt_builder/pipeline.rb      # Abstract pipeline
lib/agent_core/prompt_builder/simple_pipeline.rb  # Default: direct assembly
lib/agent_core/prompt_runner/events.rb         # Callback event system
lib/agent_core/prompt_runner/run_result.rb     # Run result
lib/agent_core/prompt_runner/runner.rb         # Core loop (sync + stream)
lib/agent_core/agent/builder.rb               # Builder pattern + serialization
lib/agent_core/agent.rb                       # Top-level Agent, chat/chat_stream

test/test_helper.rb                           # MockProvider
test/agent_core/message_test.rb               # Message, ToolCall, ContentBlock
test/agent_core/resources/chat_history_test.rb # InMemory + wrap
test/agent_core/resources/memory_test.rb       # InMemory
test/agent_core/resources/tools/registry_test.rb  # Registry + Tool + ToolResult
test/agent_core/resources/tools/policy_test.rb # Decision + Base
test/agent_core/prompt_builder/simple_pipeline_test.rb
test/agent_core/prompt_runner/runner_test.rb   # Sync, streaming, tools, policy, events
test/agent_core/agent_test.rb                 # Build, chat, stream, serialize, reset
```

### Plan Compliance Checklist

| Plan Item | Status | Notes |
|-----------|--------|-------|
| Message + ContentBlock + ToolCall + StreamEvent | ✅ | |
| ChatHistory (Base + InMemory) | ✅ | |
| Memory (Base + InMemory) | ✅ | |
| Provider (Base + Response + Usage) | ✅ | Missing `#models` method from plan |
| Tool + ToolResult + ToolDefinition | ✅ | ToolDefinition folded into Tool#to_definition |
| Tools::Registry | ✅ | |
| Tool Policy (Base + Decision) | ✅ | |
| PromptBuilder (Context, Pipeline, SimplePipeline, BuiltPrompt) | ✅ | |
| PromptRunner (Runner, Events, RunResult) | ✅ | |
| Agent (Builder, config serialization) | ✅ | |
| Tests for all of the above | ✅ | 83 tests |

### What Was Deferred to Phase 2

- MCP Client (JsonRpcClient, Transport::Base, StdIO, StreamableHTTP)
- Skills (Store, FileSystemStore)
- Registry#register_skill (only register_mcp_client exists)
