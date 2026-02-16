require "test_helper"

class ContinuationRecordTest < ActiveSupport::TestCase
  test "claim_for_resume! transitions current -> consuming (with lock token + attempts)" do
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

    token = ContinuationRecord.claim_for_resume!(run_id: "run_1", continuation_id: "cont_1", reclaim_after: 5.minutes)
    assert token

    record.reload
    assert_equal "consuming", record.status
    assert record.consuming_at
    assert_equal token, record.resume_lock_token
    assert_equal 1, record.resume_attempts
  end

  test "claim_for_resume! raises BusyContinuationError when consuming within TTL" do
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

    ContinuationRecord.claim_for_resume!(run_id: "run_2", continuation_id: "cont_2", reclaim_after: 5.minutes)

    assert_raises(ContinuationRecord::BusyContinuationError) do
      ContinuationRecord.claim_for_resume!(run_id: "run_2", continuation_id: "cont_2", reclaim_after: 5.minutes)
    end
  end

  test "claim_for_resume! can reclaim a stale consuming lock after TTL" do
    provider =
      LLMProvider.create!(
        name: "P3",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M3", model: "m1", enabled: true)

    record =
      ContinuationRecord.create!(
        run_id: "run_3",
        continuation_id: "cont_3",
        llm_model: llm_model,
        tooling_key: "default",
        payload: { "schema_version" => 1 },
      )

    token1 = ContinuationRecord.claim_for_resume!(run_id: "run_3", continuation_id: "cont_3", reclaim_after: 5.minutes)
    record.reload
    record.update!(consuming_at: 10.minutes.ago)

    token2 = ContinuationRecord.claim_for_resume!(run_id: "run_3", continuation_id: "cont_3", reclaim_after: 5.minutes)
    assert token2
    refute_equal token1, token2

    record.reload
    assert_equal "consuming", record.status
    assert_equal token2, record.resume_lock_token
    assert_equal 2, record.resume_attempts
    assert record.consuming_at > 2.minutes.ago
  end

  test "mark_consumed! transitions consuming -> consumed (token match required)" do
    provider =
      LLMProvider.create!(
        name: "P4",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M4", model: "m1", enabled: true)

    record =
      ContinuationRecord.create!(
        run_id: "run_4",
        continuation_id: "cont_4",
        llm_model: llm_model,
        tooling_key: "default",
        payload: { "schema_version" => 1 },
      )

    token = ContinuationRecord.claim_for_resume!(run_id: "run_4", continuation_id: "cont_4", reclaim_after: 5.minutes)

    assert ContinuationRecord.mark_consumed!(run_id: "run_4", continuation_id: "cont_4", lock_token: token)

    record.reload
    assert_equal "consumed", record.status
    assert record.consumed_at
    assert_nil record.resume_lock_token
    assert_nil record.consuming_at
  end

  test "release_after_failure! transitions consuming -> current and stores last error info" do
    provider =
      LLMProvider.create!(
        name: "P5",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M5", model: "m1", enabled: true)

    record =
      ContinuationRecord.create!(
        run_id: "run_5",
        continuation_id: "cont_5",
        llm_model: llm_model,
        tooling_key: "default",
        payload: { "schema_version" => 1 },
      )

    token = ContinuationRecord.claim_for_resume!(run_id: "run_5", continuation_id: "cont_5", reclaim_after: 5.minutes)

    error = StandardError.new("boom")
    assert ContinuationRecord.release_after_failure!(run_id: "run_5", continuation_id: "cont_5", lock_token: token, error: error)

    record.reload
    assert_equal "current", record.status
    assert_nil record.consuming_at
    assert_nil record.resume_lock_token
    assert_equal "StandardError", record.last_resume_error_class
    assert_equal "boom", record.last_resume_error_message
    assert record.last_resume_error_at
  end

  test "cancel_run! marks current and consuming continuations as cancelled" do
    provider =
      LLMProvider.create!(
        name: "P6",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M6", model: "m1", enabled: true)

    current =
      ContinuationRecord.create!(
        run_id: "run_6",
        continuation_id: "cont_current",
        llm_model: llm_model,
        tooling_key: "default",
        status: "current",
        payload: { "schema_version" => 1 },
      )

    consuming =
      ContinuationRecord.create!(
        run_id: "run_6",
        continuation_id: "cont_consuming",
        llm_model: llm_model,
        tooling_key: "default",
        status: "consuming",
        consuming_at: 1.minute.ago,
        resume_lock_token: "tok",
        payload: { "schema_version" => 1 },
      )

    updated = ContinuationRecord.cancel_run!(run_id: "run_6", reason: "user_cancelled")
    assert_equal 2, updated

    current.reload
    consuming.reload

    assert_equal "cancelled", current.status
    assert current.cancelled_at

    assert_equal "cancelled", consuming.status
    assert consuming.cancelled_at
    assert_nil consuming.consuming_at
    assert_nil consuming.resume_lock_token
  end
end
