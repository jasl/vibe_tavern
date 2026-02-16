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
          skipped_cancelled: true,
        }
      end

      context_attributes = task_payload.fetch("context_attributes", {})
      tasks = Array(task_payload.fetch("tasks"))

      enqueued = []
      reclaimed = []
      reenqueued = []

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

        if ToolResultRecord.reclaim_stale_executing!(run_id: run_id, tool_call_id: tool_call_id)
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
