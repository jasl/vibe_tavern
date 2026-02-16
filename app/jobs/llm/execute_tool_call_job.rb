# frozen_string_literal: true

require "agent_core"

module LLM
  class ExecuteToolCallJob < ApplicationJob
    queue_as :default

    def perform(run_id:, tooling_key:, tool_call_id:, executed_name:, arguments:, context_attributes: {})
      run_id = run_id.to_s
      tool_call_id = tool_call_id.to_s
      executed_name = executed_name.to_s
      tooling_key = tooling_key.to_s

      args = arguments.is_a?(Hash) ? AgentCore::Utils.deep_stringify_keys(arguments) : {}
      ctx_attrs = normalize_context_attributes(context_attributes)

      context =
        AgentCore::ExecutionContext
          .from(ctx_attrs)
          .with(run_id: run_id)

      registry = LLM::Tooling.registry(tooling_key: tooling_key, context_attributes: ctx_attrs)

      result =
        begin
          registry.execute(name: executed_name, arguments: args, context: context)
        rescue => e
          AgentCore::Resources::Tools::ToolResult.error(text: "Tool execution failed: #{e.message}")
        end

      ToolResultRecord.upsert_result!(
        run_id: run_id,
        tool_call_id: tool_call_id,
        executed_name: executed_name,
        tool_result: result,
      )
    end

    private

    def normalize_context_attributes(value)
      case value
      when nil
        {}
      when Hash
        AgentCore::Utils.deep_symbolize_keys(value)
      else
        {}
      end
    end
  end
end
