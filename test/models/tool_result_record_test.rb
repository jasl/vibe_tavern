require "test_helper"

class ToolResultRecordTest < ActiveSupport::TestCase
  test "reserve! creates once and is idempotent" do
    r1, reserved1 =
      ToolResultRecord.reserve!(
        run_id: "run_1",
        tool_call_id: "tc_1",
        executed_name: "echo",
      )

    assert reserved1
    assert_equal 1, ToolResultRecord.count
    assert_equal "queued", r1.status
    assert r1.enqueued_at
    assert_nil r1.tool_result

    r2, reserved2 =
      ToolResultRecord.reserve!(
        run_id: "run_1",
        tool_call_id: "tc_1",
        executed_name: "echo",
      )

    refute reserved2
    assert_equal r1.id, r2.id
    assert_equal 1, ToolResultRecord.count
  end

  test "claim_for_execution! transitions queued -> executing once" do
    ToolResultRecord.reserve!(run_id: "run_2", tool_call_id: "tc_1", executed_name: "echo")

    assert ToolResultRecord.claim_for_execution!(run_id: "run_2", tool_call_id: "tc_1", job_id: "j1")
    refute ToolResultRecord.claim_for_execution!(run_id: "run_2", tool_call_id: "tc_1", job_id: "j2")

    record = ToolResultRecord.find_by!(run_id: "run_2", tool_call_id: "tc_1")
    assert_equal "executing", record.status
    assert_equal "j1", record.locked_by
    assert record.started_at
  end

  test "complete! transitions executing -> ready and stores payload" do
    ToolResultRecord.reserve!(run_id: "run_3", tool_call_id: "tc_1", executed_name: "echo")
    assert ToolResultRecord.claim_for_execution!(run_id: "run_3", tool_call_id: "tc_1", job_id: "j1")

    result = AgentCore::Resources::Tools::ToolResult.success(text: "ok", metadata: { duration_ms: 1.0 })
    assert ToolResultRecord.complete!(run_id: "run_3", tool_call_id: "tc_1", job_id: "j1", tool_result: result)

    record = ToolResultRecord.find_by!(run_id: "run_3", tool_call_id: "tc_1")
    assert_equal "ready", record.status
    assert record.tool_result
    assert record.finished_at
  end

  test "upsert_result! can fulfill an existing queued reservation" do
    ToolResultRecord.reserve!(run_id: "run_4", tool_call_id: "tc_1", executed_name: "echo")

    result = AgentCore::Resources::Tools::ToolResult.success(text: "ok", metadata: { duration_ms: 1.0 })

    record =
      ToolResultRecord.upsert_result!(
        run_id: "run_4",
        tool_call_id: "tc_1",
        executed_name: "echo",
        tool_result: result,
      )

    record.reload
    assert_equal "ready", record.status
    assert record.tool_result
    assert record.finished_at
  end

  test "upsert_result! raises on conflicting payloads for the same tool_call_id" do
    ToolResultRecord.upsert_result!(
      run_id: "run_5",
      tool_call_id: "tc_1",
      executed_name: "echo",
      tool_result: AgentCore::Resources::Tools::ToolResult.success(text: "a"),
    )

    assert_raises(ArgumentError) do
      ToolResultRecord.upsert_result!(
        run_id: "run_5",
        tool_call_id: "tc_1",
        executed_name: "echo",
        tool_result: AgentCore::Resources::Tools::ToolResult.success(text: "b"),
      )
    end
  end
end
