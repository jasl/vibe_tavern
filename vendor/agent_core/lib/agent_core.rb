# frozen_string_literal: true

require_relative "agent_core/version"
require_relative "agent_core/errors"
require_relative "agent_core/configuration"
require_relative "agent_core/utils"

# Observability (library-agnostic tracing/instrumentation)
require_relative "agent_core/observability/instrumenter"
require_relative "agent_core/observability/null_instrumenter"
require_relative "agent_core/observability/trace_recorder"

# Execution context (run_id, attributes, instrumenter)
require_relative "agent_core/execution_context"

# Core data types
require_relative "agent_core/message"
require_relative "agent_core/stream_event"

# Resources
require_relative "agent_core/resources/provider/base"
require_relative "agent_core/resources/provider/response"
require_relative "agent_core/resources/chat_history/base"
require_relative "agent_core/resources/chat_history/in_memory"
require_relative "agent_core/resources/memory/base"
require_relative "agent_core/resources/memory/in_memory"
require_relative "agent_core/resources/conversation_state/base"
require_relative "agent_core/resources/conversation_state/in_memory"
require_relative "agent_core/resources/tools/tool"
require_relative "agent_core/resources/tools/tool_result"
require_relative "agent_core/resources/tools/registry"
require_relative "agent_core/resources/tools/policy/base"
require_relative "agent_core/resources/tools/policy/deny_all"
require_relative "agent_core/resources/tools/policy/allow_all"
require_relative "agent_core/resources/token_counter/base"
require_relative "agent_core/resources/token_counter/heuristic"

# Prompt injections
require_relative "agent_core/resources/prompt_injections/item"
require_relative "agent_core/resources/prompt_injections/truncation"
require_relative "agent_core/resources/prompt_injections/source/base"
require_relative "agent_core/resources/prompt_injections/text_store/base"
require_relative "agent_core/resources/prompt_injections/text_store/in_memory"
require_relative "agent_core/resources/prompt_injections/sources/provided"
require_relative "agent_core/resources/prompt_injections/sources/text_store_entries"
require_relative "agent_core/resources/prompt_injections/sources/file_set"
require_relative "agent_core/resources/prompt_injections/sources/repo_docs"
require_relative "agent_core/resources/prompt_injections/factory"

# MCP (Model Context Protocol)
require_relative "agent_core/mcp"

# Skills
require_relative "agent_core/resources/skills/skill_metadata"
require_relative "agent_core/resources/skills/skill"
require_relative "agent_core/resources/skills/frontmatter"
require_relative "agent_core/resources/skills/store"
require_relative "agent_core/resources/skills/file_system_store"
require_relative "agent_core/resources/skills/prompt_fragment"
require_relative "agent_core/resources/skills/tools"

# Prompt Builder
require_relative "agent_core/prompt_builder/context"
require_relative "agent_core/prompt_builder/built_prompt"
require_relative "agent_core/prompt_builder/pipeline"
require_relative "agent_core/prompt_builder/simple_pipeline"

# Prompt Runner
require_relative "agent_core/prompt_runner/events"
require_relative "agent_core/prompt_runner/run_result"
require_relative "agent_core/prompt_runner/tool_execution_utils"
require_relative "agent_core/prompt_runner/tool_executor"
require_relative "agent_core/prompt_runner/continuation_codec"
require_relative "agent_core/prompt_runner/tool_task_codec"
require_relative "agent_core/prompt_runner/runner"

# Context management (auto-compaction)
require_relative "agent_core/context_management/summarizer"
require_relative "agent_core/context_management/context_manager"

# Agent (top-level)
require_relative "agent_core/agent"

module AgentCore
  # Convenience: build an agent.
  def self.build(&block)
    Agent.build(&block)
  end
end
