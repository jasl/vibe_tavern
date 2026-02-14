# frozen_string_literal: true

require_relative "agent_core/version"
require_relative "agent_core/errors"
require_relative "agent_core/utils"

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
require_relative "agent_core/resources/tools/tool"
require_relative "agent_core/resources/tools/tool_result"
require_relative "agent_core/resources/tools/registry"
require_relative "agent_core/resources/tools/policy/base"
require_relative "agent_core/resources/token_counter/base"
require_relative "agent_core/resources/token_counter/heuristic"

# Prompt Builder
require_relative "agent_core/prompt_builder/context"
require_relative "agent_core/prompt_builder/built_prompt"
require_relative "agent_core/prompt_builder/pipeline"
require_relative "agent_core/prompt_builder/simple_pipeline"

# Prompt Runner
require_relative "agent_core/prompt_runner/events"
require_relative "agent_core/prompt_runner/run_result"
require_relative "agent_core/prompt_runner/runner"

# Agent (top-level)
require_relative "agent_core/agent"

module AgentCore
  # Convenience: build an agent.
  def self.build(&block)
    Agent.build(&block)
  end
end
