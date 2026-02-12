# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolsBuilder
      class ExecutorRouter
        def initialize(skills_executor: nil, mcp_executor: nil, default_executor: nil)
          @skills_executor = skills_executor
          @mcp_executor = mcp_executor
          @default_executor = default_executor
          @executor_accepts_tool_call_id = {}
        end

        def call(name:, args:, tool_call_id: nil)
          tool_name = name.to_s
          args = args.is_a?(Hash) ? args : {}

          executor = resolve_executor(tool_name)
          unless executor
            return error_envelope(tool_name, code: "TOOL_NOT_IMPLEMENTED", message: "Tool not implemented: #{tool_name}")
          end

          tool_call_id = tool_call_id.to_s
          if !tool_call_id.empty? && executor_accepts_tool_call_id?(executor)
            executor.call(name: tool_name, args: args, tool_call_id: tool_call_id)
          else
            executor.call(name: tool_name, args: args)
          end
        rescue ArgumentError => e
          error_envelope(tool_name, code: "ARGUMENT_ERROR", message: e.message)
        rescue StandardError => e
          error_envelope(tool_name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
        end

        private

        def resolve_executor(tool_name)
          if tool_name.start_with?("skills_")
            @skills_executor
          elsif tool_name.start_with?("mcp_")
            @mcp_executor
          else
            @default_executor
          end
        end

        def executor_accepts_tool_call_id?(executor)
          cached = @executor_accepts_tool_call_id[executor.object_id]
          return cached unless cached.nil?

          params = callable_parameters(executor)
          accepts =
            params.any? do |type, name|
              type == :keyrest || (%i[key keyreq].include?(type) && name == :tool_call_id)
            end

          @executor_accepts_tool_call_id[executor.object_id] = accepts
          accepts
        end

        def callable_parameters(callable)
          return [] unless callable

          if callable.respond_to?(:parameters)
            callable.parameters
          else
            callable.method(:call).parameters
          end
        rescue NameError, TypeError
          []
        end

        def error_envelope(tool_name, code:, message:)
          {
            ok: false,
            tool_name: tool_name,
            data: {},
            warnings: [],
            errors: [{ code: code.to_s, message: message.to_s }],
          }
        end
      end
    end
  end
end
