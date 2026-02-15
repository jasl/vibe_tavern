# frozen_string_literal: true

require "thread"

module AgentCore
  module PromptRunner
    # Tool execution strategy.
    #
    # Runner delegates allowed tool calls to a ToolExecutor. This enables:
    # - synchronous inline execution (default)
    # - same-turn parallel execution (opt-in per tool)
    # - deferring execution to the app (pause/resume with external results)
    module ToolExecutor
      ExecutionRequest =
        Data.define(
          :tool_call_id,
          :name,
          :executed_name,
          :arguments,
          :arguments_summary,
          :source,
        )

      CompletedExecution =
        Data.define(
          :tool_call_id,
          :name,
          :executed_name,
          :source,
          :arguments_summary,
          :result,
          :result_summary,
          :error,
          :duration_ms,
        ) do
          def error? = error == true
        end

      Result =
        Data.define(
          :completed,
          :deferred,
        )

      class Base
        def deferred? = false

        def execute(requests:, tools_registry:, execution_context:, max_tool_output_bytes:)
          raise AgentCore::NotImplementedError, "#{self.class}#execute must be implemented"
        end
      end

      class Inline < Base
        def execute(requests:, tools_registry:, execution_context:, max_tool_output_bytes:)
          completed =
            Array(requests).map do |req|
              execute_one(
                req,
                tools_registry: tools_registry,
                execution_context: execution_context,
                max_tool_output_bytes: max_tool_output_bytes,
              )
            end

          Result.new(completed: completed, deferred: [])
        end

        private

        def execute_one(request, tools_registry:, execution_context:, max_tool_output_bytes:)
          instrumenter = execution_context.instrumenter
          run_id = execution_context.run_id

          payload = {
            run_id: run_id,
            tool_call_id: request.tool_call_id,
            name: request.name,
            executed_name: request.executed_name,
            source: request.source,
            arguments_summary: request.arguments_summary,
          }

          result =
            instrumenter.instrument("agent_core.tool.execute", payload) do
              res =
                begin
                  tools_registry.execute(
                    name: request.executed_name,
                    arguments: request.arguments,
                    context: execution_context
                  )
                rescue ToolNotFoundError => e
                  Resources::Tools::ToolResult.error(text: e.message)
                rescue StandardError => e
                  Resources::Tools::ToolResult.error(text: "Tool '#{request.name}' raised: #{e.message}")
                end

              res = ToolExecutionUtils.limit_tool_result(res, max_bytes: max_tool_output_bytes, tool_name: request.executed_name)

              payload[:result_error] = res.error?
              payload[:result_summary] = ToolExecutionUtils.summarize_tool_result(res)
              res
            end

          CompletedExecution.new(
            tool_call_id: request.tool_call_id,
            name: request.name,
            executed_name: request.executed_name,
            source: request.source,
            arguments_summary: request.arguments_summary,
            result: result,
            result_summary: payload[:result_summary],
            error: payload[:result_error] == true,
            duration_ms: payload[:duration_ms],
          )
        end
      end

      class DeferAll < Base
        def deferred? = true

        def execute(requests:, tools_registry:, execution_context:, max_tool_output_bytes:)
          pending =
            Array(requests).map do |req|
              PendingToolExecution.new(
                tool_call_id: req.tool_call_id,
                name: req.name,
                executed_name: req.executed_name,
                arguments: req.arguments,
                arguments_summary: req.arguments_summary,
                source: req.source,
              )
            end

          Result.new(completed: [], deferred: pending)
        end
      end

      class ThreadPool < Base
        DEFAULT_MAX_CONCURRENCY = 4

        def initialize(max_concurrency: DEFAULT_MAX_CONCURRENCY)
          @max_concurrency = Integer(max_concurrency)
          raise ArgumentError, "max_concurrency must be positive" if @max_concurrency <= 0
        end

        def execute(requests:, tools_registry:, execution_context:, max_tool_output_bytes:)
          requests = Array(requests)
          return Result.new(completed: [], deferred: []) if requests.empty?

          parallelizable, sequential =
            requests.partition do |req|
              parallelizable_tool?(tools_registry, req.executed_name)
            end

          completed_by_id = {}

          sequential.each do |req|
            completed_by_id[req.tool_call_id] =
              execute_one(
                req,
                tools_registry: tools_registry,
                execution_context: execution_context,
                max_tool_output_bytes: max_tool_output_bytes,
              )
          end

          if parallelizable.any?
            parallel_completed =
              execute_parallel(
                parallelizable,
                tools_registry: tools_registry,
                execution_context: execution_context,
                max_tool_output_bytes: max_tool_output_bytes,
              )

            parallel_completed.each do |ce|
              completed_by_id[ce.tool_call_id] = ce
            end
          end

          completed =
            requests.map do |req|
              completed_by_id.fetch(req.tool_call_id)
            end

          Result.new(completed: completed, deferred: [])
        end

        private

        def execute_parallel(requests, tools_registry:, execution_context:, max_tool_output_bytes:)
          jobs = Queue.new
          results = Queue.new

          requests.each { |r| jobs << r }

          workers = [@max_concurrency, requests.size].min
          workers.times { jobs << :__stop__ }

          threads =
            workers.times.map do
              Thread.new do
                loop do
                  req = jobs.pop
                  break if req == :__stop__

                  ce =
                    execute_one(
                      req,
                      tools_registry: tools_registry,
                      execution_context: execution_context,
                      max_tool_output_bytes: max_tool_output_bytes,
                    )

                  results << ce
                end
              end
            end

          out = Array.new(requests.size) { results.pop }
          threads.each(&:join)
          out
        end

        def execute_one(request, tools_registry:, execution_context:, max_tool_output_bytes:)
          instrumenter = execution_context.instrumenter
          run_id = execution_context.run_id

          payload = {
            run_id: run_id,
            tool_call_id: request.tool_call_id,
            name: request.name,
            executed_name: request.executed_name,
            source: request.source,
            arguments_summary: request.arguments_summary,
          }

          result =
            instrumenter.instrument("agent_core.tool.execute", payload) do
              res =
                begin
                  tools_registry.execute(
                    name: request.executed_name,
                    arguments: request.arguments,
                    context: execution_context
                  )
                rescue ToolNotFoundError => e
                  Resources::Tools::ToolResult.error(text: e.message)
                rescue StandardError => e
                  Resources::Tools::ToolResult.error(text: "Tool '#{request.name}' raised: #{e.message}")
                end

              res = ToolExecutionUtils.limit_tool_result(res, max_bytes: max_tool_output_bytes, tool_name: request.executed_name)

              payload[:result_error] = res.error?
              payload[:result_summary] = ToolExecutionUtils.summarize_tool_result(res)
              res
            end

          CompletedExecution.new(
            tool_call_id: request.tool_call_id,
            name: request.name,
            executed_name: request.executed_name,
            source: request.source,
            arguments_summary: request.arguments_summary,
            result: result,
            result_summary: payload[:result_summary],
            error: payload[:result_error] == true,
            duration_ms: payload[:duration_ms],
          )
        end

        def parallelizable_tool?(tools_registry, tool_name)
          return false unless tools_registry&.respond_to?(:find)

          info = tools_registry.find(tool_name)
          return false unless info.is_a?(Resources::Tools::Tool)

          meta = info.metadata
          meta.is_a?(Hash) && meta[:parallelizable] == true
        rescue StandardError
          false
        end
      end
    end
  end
end
