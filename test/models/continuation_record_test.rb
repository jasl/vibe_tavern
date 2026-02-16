require "test_helper"

class ContinuationRecordTest < ActiveSupport::TestCase
  test "consume! marks a current continuation as consumed" do
    provider =
      LLMProvider.create!(
        name: "P",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M", model: "m1", enabled: true)

    record =
      ContinuationRecord.create!(
        run_id: "run_1",
        continuation_id: "cont_1",
        llm_model: llm_model,
        tooling_key: "default",
        payload: { "schema_version" => 1 },
      )

    assert_equal "current", record.status
    assert_nil record.consumed_at

    assert ContinuationRecord.consume!(run_id: "run_1", continuation_id: "cont_1")

    record.reload
    assert_equal "consumed", record.status
    assert record.consumed_at
  end

  test "consume! raises StaleContinuationError when already consumed" do
    provider =
      LLMProvider.create!(
        name: "P2",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M2", model: "m1", enabled: true)

    ContinuationRecord.create!(
      run_id: "run_2",
      continuation_id: "cont_2",
      llm_model: llm_model,
      tooling_key: "default",
      payload: { "schema_version" => 1 },
    )

    ContinuationRecord.consume!(run_id: "run_2", continuation_id: "cont_2")

    assert_raises(ContinuationRecord::StaleContinuationError) do
      ContinuationRecord.consume!(run_id: "run_2", continuation_id: "cont_2")
    end
  end
end
