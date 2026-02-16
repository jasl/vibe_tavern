require "test_helper"

class LLMToolChatDeferredExecutionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class SequencedFakeClient
    attr_reader :requests

    def initialize(bodies)
      @requests = []
      @bodies = Array(bodies).dup
    end

    def chat_completions(**params)
      @requests << params
      body = @bodies.shift || raise("fake client has no more responses")
      SimpleInference::Response.new(status: 200, headers: {}, body: body, raw_body: "{}")
    end
  end

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "deferred tool execution can be resumed and is stale-protected by continuation_id" do
    provider =
      LLMProvider.create!(
        name: "X",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", enabled: true)

    client =
      SequencedFakeClient.new(
        [
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "",
                  "tool_calls" => [
                    {
                      "id" => "tc_1",
                      "type" => "function",
                      "function" => { "name" => "echo", "arguments" => "{\"text\":\"hello\"}" },
                    },
                    {
                      "id" => "tc_2",
                      "type" => "function",
                      "function" => { "name" => "noop", "arguments" => "{}" },
                    },
                  ],
                },
                "finish_reason" => "tool_calls",
              },
            ],
          },
          {
            "choices" => [
              {
                "message" => { "role" => "assistant", "content" => "done" },
                "finish_reason" => "stop",
              },
            ],
          },
        ],
      )

    started =
      LLM::RunToolChat.call(
        llm_model: llm_model,
        user_text: "hi",
        client: client,
        context: { tenant_id: "t1" },
        tooling_key: "default",
        context_keys: %i[tenant_id],
      )

    assert started.success?, started.errors.inspect

    started_run = started.value.fetch(:run_result)
    assert started_run.awaiting_tool_results?

    run_id = started.value.fetch(:run_id)
    continuation_id = started.value.fetch(:continuation_id)

    record = ContinuationRecord.find_by!(run_id: run_id, continuation_id: continuation_id)
    assert_equal "current", record.status
    assert_equal "t1", record.payload.dig("context_attributes", "tenant_id")

    assert_equal 2, enqueued_jobs.count { |j| j.fetch(:job) == LLM::ExecuteToolCallJob }

    assert_equal 2, ToolResultRecord.where(run_id: run_id).count
    assert_equal 2, ToolResultRecord.where(run_id: run_id, status: "queued").count

    tool_jobs =
      enqueued_jobs
        .select { |j| j.fetch(:job) == LLM::ExecuteToolCallJob }
        .map do |j|
          args = j.fetch(:args).first
          args = args.is_a?(Hash) ? args.transform_keys { |k| k.to_s.to_sym } : {}
          args.delete(:_aj_ruby2_keywords)
          args.delete(:_aj_symbol_keys)
          args
        end

    clear_enqueued_jobs

    first_args = tool_jobs.find { |a| a[:tool_call_id].to_s == "tc_1" }
    second_args = tool_jobs.find { |a| a[:tool_call_id].to_s == "tc_2" }
    assert first_args
    assert second_args

    LLM::ExecuteToolCallJob.new.perform(**first_args)

    assert_equal 2, ToolResultRecord.where(run_id: run_id).count
    assert_equal 1, ToolResultRecord.ready.where(run_id: run_id).count
    assert_equal 1, ToolResultRecord.where(run_id: run_id, status: "queued").count

    resumed =
      LLM::ResumeToolChat.call(
        run_id: run_id,
        continuation_id: continuation_id,
        client: client,
      )

    assert resumed.success?, resumed.errors.inspect
    assert_equal "consumed", record.reload.status
    paused_again = resumed.value.fetch(:run_result)
    assert paused_again.awaiting_tool_results?

    next_record = ContinuationRecord.current_for_run!(run_id)
    assert_equal record.continuation_id, next_record.parent_continuation_id
    assert_equal "t1", next_record.payload.dig("context_attributes", "tenant_id")

    assert_equal 0, enqueued_jobs.count { |j| j.fetch(:job) == LLM::ExecuteToolCallJob }

    LLM::ExecuteToolCallJob.new.perform(**second_args)

    assert_equal 2, ToolResultRecord.where(run_id: run_id).count
    assert_equal 2, ToolResultRecord.ready.where(run_id: run_id).count

    resumed_final =
      LLM::ResumeToolChat.call(
        run_id: run_id,
        continuation_id: next_record.continuation_id,
        client: client,
      )

    assert resumed_final.success?, resumed_final.errors.inspect
    final = resumed_final.value.fetch(:run_result)
    assert_equal "done", final.final_message&.text

    stale =
      LLM::ResumeToolChat.call(
        run_id: run_id,
        continuation_id: next_record.continuation_id,
        client: client,
      )

    assert stale.failure?
    assert_equal "STALE_CONTINUATION", stale.code
  end

  test "stale executing tool tasks are reclaimed and re-enqueued when resuming without results" do
    provider =
      LLMProvider.create!(
        name: "Y",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "M2", model: "m1", enabled: true)

    client =
      SequencedFakeClient.new(
        [
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "",
                  "tool_calls" => [
                    {
                      "id" => "tc_1",
                      "type" => "function",
                      "function" => { "name" => "echo", "arguments" => "{\"text\":\"hello\"}" },
                    },
                    {
                      "id" => "tc_2",
                      "type" => "function",
                      "function" => { "name" => "noop", "arguments" => "{}" },
                    },
                  ],
                },
                "finish_reason" => "tool_calls",
              },
            ],
          },
        ],
      )

    started =
      LLM::RunToolChat.call(
        llm_model: llm_model,
        user_text: "hi",
        client: client,
        context: { tenant_id: "t1" },
        tooling_key: "default",
        context_keys: %i[tenant_id],
      )

    assert started.success?, started.errors.inspect

    run_id = started.value.fetch(:run_id)
    continuation_id = started.value.fetch(:continuation_id)

    assert_equal 2, ToolResultRecord.where(run_id: run_id, status: "queued").count

    assert ToolResultRecord.claim_for_execution!(run_id: run_id, tool_call_id: "tc_1", job_id: "j1")
    ToolResultRecord.find_by!(run_id: run_id, tool_call_id: "tc_1").update!(started_at: 20.minutes.ago)

    clear_enqueued_jobs

    resumed =
      LLM::ResumeToolChat.call(
        run_id: run_id,
        continuation_id: continuation_id,
        client: client,
      )

    assert resumed.failure?
    assert_equal "NO_TOOL_RESULTS_AVAILABLE", resumed.code

    assert_equal 1, enqueued_jobs.count { |j| j.fetch(:job) == LLM::ExecuteToolCallJob }

    tc1 = ToolResultRecord.find_by!(run_id: run_id, tool_call_id: "tc_1")
    assert_equal "queued", tc1.status
    assert_nil tc1.locked_by
    assert_nil tc1.started_at
  end
end
