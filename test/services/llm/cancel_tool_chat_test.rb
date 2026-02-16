require "test_helper"

class LLMCancelToolChatTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class SequencedFakeClient
    def initialize(bodies)
      @bodies = Array(bodies).dup
    end

    def chat_completions(**_params)
      body = @bodies.shift || raise("fake client has no more responses")
      SimpleInference::Response.new(status: 200, headers: {}, body: body, raw_body: "{}")
    end
  end

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "cancel_tool_chat marks run cancelled and tool jobs do not write results" do
    provider =
      LLMProvider.create!(
        name: "C",
        base_url: "http://example.test",
        api_prefix: "/v1",
        headers: {},
        llm_options_defaults: {},
      )

    llm_model = LLMModel.create!(llm_provider: provider, name: "CM", model: "m1", enabled: true)

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
    assert started.value.fetch(:run_result).awaiting_tool_results?

    run_id = started.value.fetch(:run_id)
    continuation_id = started.value.fetch(:continuation_id)

    assert_equal 2, ToolResultRecord.where(run_id: run_id, status: "queued").count

    cancelled = LLM::CancelToolChat.call(run_id: run_id, reason: "user_cancelled")
    assert cancelled.success?, cancelled.errors.inspect

    assert ContinuationRecord.where(run_id: run_id, status: "cancelled").exists?
    assert_equal 2, ToolResultRecord.where(run_id: run_id, status: "cancelled").count

    perform_enqueued_jobs

    assert_equal 0, ToolResultRecord.where(run_id: run_id, status: "ready").count
    assert_equal 2, ToolResultRecord.where(run_id: run_id, status: "cancelled").count

    resumed =
      LLM::ResumeToolChat.call(
        run_id: run_id,
        continuation_id: continuation_id,
        client: client,
      )

    assert resumed.failure?
    assert_equal "RUN_CANCELLED", resumed.code
  end
end
