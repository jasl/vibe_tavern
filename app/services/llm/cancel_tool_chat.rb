# frozen_string_literal: true

module LLM
  class CancelToolChat
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(run_id:, reason: nil)
      @run_id = run_id.to_s
      @reason = reason
    end

    def call
      cancelled_continuations = ContinuationRecord.cancel_run!(run_id: run_id, reason: reason)
      cancelled_tool_tasks = ToolResultRecord.cancel_run!(run_id: run_id)

      Result.success(
        value: {
          run_id: run_id,
          cancelled_continuations: cancelled_continuations,
          cancelled_tool_tasks: cancelled_tool_tasks,
        },
      )
    end

    private

    attr_reader :run_id, :reason
  end
end
