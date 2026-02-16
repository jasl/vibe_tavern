require "test_helper"

class LLMEnqueueToolTasksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "non-retryable stale executing tasks are failed to ready and not enqueued" do
    run_id = "run_1"

    ToolResultRecord.reserve!(run_id: run_id, tool_call_id: "tc_1", executed_name: "unknown_tool")
    assert ToolResultRecord.claim_for_execution!(run_id: run_id, tool_call_id: "tc_1", job_id: "j1")
    ToolResultRecord.find_by!(run_id: run_id, tool_call_id: "tc_1").update!(started_at: 20.minutes.ago)

    task_payload = {
      "run_id" => run_id,
      "context_attributes" => {},
      "tasks" => [
        {
          "tool_call_id" => "tc_1",
          "executed_name" => "unknown_tool",
          "arguments" => {},
        },
      ],
    }

    stats = LLM::EnqueueToolTasks.call(task_payload: task_payload, tooling_key: "default")

    record = ToolResultRecord.find_by!(run_id: run_id, tool_call_id: "tc_1")
    assert_equal "ready", record.status
    assert record.tool_result

    result = AgentCore::Resources::Tools::ToolResult.from_h(record.tool_result)
    assert result.error?
    assert_includes result.text, ToolResultRecord::STALE_EXECUTION_NOT_RETRIED_MESSAGE

    assert_empty enqueued_jobs
    assert_equal ["tc_1"], stats.fetch(:failed)
  end
end
