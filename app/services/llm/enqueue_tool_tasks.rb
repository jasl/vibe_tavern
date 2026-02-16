# frozen_string_literal: true

module LLM
  class EnqueueToolTasks
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(task_payload:, tooling_key:)
      @task_payload = task_payload
      @tooling_key = tooling_key.to_s
    end

    def call
      run_id = task_payload.fetch("run_id").to_s

      if ContinuationRecord.where(run_id: run_id, status: "cancelled").exists?
        return {
          enqueued: [],
          reclaimed: [],
          reenqueued: [],
          failed: [],
          skipped_cancelled: true,
        }
      end

      context_attributes = task_payload.fetch("context_attributes", {})
      registry = LLM::Tooling.registry(tooling_key: tooling_key, context_attributes: context_attributes)
      tasks = Array(task_payload.fetch("tasks"))

      enqueued = []
      reclaimed = []
      reenqueued = []
      failed = []

      tasks.each do |t|
        tool_call_id = t.fetch("tool_call_id").to_s
        executed_name = t.fetch("executed_name").to_s

        record, reserved =
          ToolResultRecord.reserve!(
            run_id: run_id,
            tool_call_id: tool_call_id,
            executed_name: executed_name,
          )

        next if record.status == "ready" || record.status == "cancelled"

        tool_info = registry.find(executed_name)
        retryable = tool_info.is_a?(AgentCore::Resources::Tools::Tool) && tool_info.metadata[:retryable] == true

        if reserved
          enqueue_task!(
            run_id: run_id,
            tool_call_id: tool_call_id,
            executed_name: executed_name,
            arguments: t.fetch("arguments"),
            context_attributes: context_attributes,
          )
          enqueued << tool_call_id
          next
        end

        if retryable && ToolResultRecord.reclaim_stale_executing!(run_id: run_id, tool_call_id: tool_call_id)
          enqueue_task!(
            run_id: run_id,
            tool_call_id: tool_call_id,
            executed_name: executed_name,
            arguments: t.fetch("arguments"),
            context_attributes: context_attributes,
          )
          reclaimed << tool_call_id
          enqueued << tool_call_id
          next
        end

        if !retryable && ToolResultRecord.fail_stale_executing!(run_id: run_id, tool_call_id: tool_call_id)
          failed << tool_call_id
          next
        end

        if ToolResultRecord.reenqueue_stale_queued!(run_id: run_id, tool_call_id: tool_call_id)
          enqueue_task!(
            run_id: run_id,
            tool_call_id: tool_call_id,
            executed_name: executed_name,
            arguments: t.fetch("arguments"),
            context_attributes: context_attributes,
          )
          reenqueued << tool_call_id
          enqueued << tool_call_id
        end
      end

      {
        enqueued: enqueued,
        reclaimed: reclaimed,
        reenqueued: reenqueued,
        failed: failed,
        skipped_cancelled: false,
      }
    end

    private

    attr_reader :task_payload, :tooling_key

    def enqueue_task!(run_id:, tool_call_id:, executed_name:, arguments:, context_attributes:)
      LLM::ExecuteToolCallJob.perform_later(
        run_id: run_id,
        tooling_key: tooling_key,
        tool_call_id: tool_call_id,
        executed_name: executed_name,
        arguments: arguments,
        context_attributes: context_attributes,
      )
    end
  end
end
