require "test_helper"

class ToolResultRecordTest < ActiveSupport::TestCase
  test "upsert_result! creates and is idempotent for identical payloads" do
    result = AgentCore::Resources::Tools::ToolResult.success(text: "ok", metadata: { duration_ms: 1.0 })

    r1 =
      ToolResultRecord.upsert_result!(
        run_id: "run_1",
        tool_call_id: "tc_1",
        executed_name: "echo",
        tool_result: result,
      )

    assert_equal 1, ToolResultRecord.count
    assert_equal "echo", r1.executed_name

    r2 =
      ToolResultRecord.upsert_result!(
        run_id: "run_1",
        tool_call_id: "tc_1",
        executed_name: "echo",
        tool_result: result,
      )

    assert_equal r1.id, r2.id
    assert_equal 1, ToolResultRecord.count
  end

  test "upsert_result! raises on conflicting payloads for the same tool_call_id" do
    ToolResultRecord.upsert_result!(
      run_id: "run_2",
      tool_call_id: "tc_1",
      executed_name: "echo",
      tool_result: AgentCore::Resources::Tools::ToolResult.success(text: "a"),
    )

    assert_raises(ArgumentError) do
      ToolResultRecord.upsert_result!(
        run_id: "run_2",
        tool_call_id: "tc_1",
        executed_name: "echo",
        tool_result: AgentCore::Resources::Tools::ToolResult.success(text: "b"),
      )
    end
  end
end
