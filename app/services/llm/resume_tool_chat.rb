# frozen_string_literal: true

require "agent_core"
require "agent_core/resources/provider/simple_inference_provider"

module LLM
  class ResumeToolChat
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(run_id:, continuation_id:, client: nil)
      @run_id = run_id.to_s
      @continuation_id = continuation_id.to_s
      @client = client
    end

    def call
      record =
        ContinuationRecord.find_by(run_id: run_id, continuation_id: continuation_id)

      return Result.failure(errors: ["continuation not found"], code: "CONTINUATION_NOT_FOUND", value: { run_id: run_id }) unless record

      continuation = AgentCore::PromptRunner::ContinuationCodec.load(record.payload)

      wanted_tool_call_ids = resumeable_tool_call_ids(continuation)
      tool_results = load_tool_results(run_id: run_id, tool_call_ids: wanted_tool_call_ids)

      if tool_results.empty?
        return Result.failure(
          errors: ["no tool results available"],
          code: "NO_TOOL_RESULTS_AVAILABLE",
          value: { run_id: run_id, continuation_id: continuation_id },
        )
      end

      lock_token =
        begin
          ContinuationRecord.claim_for_resume!(run_id: run_id, continuation_id: continuation_id, reclaim_after: 5.minutes)
        rescue ContinuationRecord::BusyContinuationError => e
          return Result.failure(errors: [e.message], code: "CONTINUATION_BUSY", value: { run_id: run_id, continuation_id: continuation_id })
        rescue ContinuationRecord::StaleContinuationError => e
          return Result.failure(errors: [e.message], code: "STALE_CONTINUATION", value: { run_id: run_id, continuation_id: continuation_id })
        end

      llm_model = record.llm_model
      tooling_key = record.tooling_key.to_s

      provider =
        AgentCore::Resources::Provider::SimpleInferenceProvider.new(
          client: effective_client(llm_model),
        )

      tools_registry = LLM::Tooling.registry(tooling_key: tooling_key, context_attributes: continuation.context_attributes)
      tool_policy = LLM::Tooling.policy(tooling_key: tooling_key, context_attributes: continuation.context_attributes)

      session =
        AgentCore::Contrib::AgentSession.new(
          provider: provider,
          model: llm_model.model,
          system_prompt: "",
          history: continuation.messages,
          llm_options: {},
          tools_registry: tools_registry,
          tool_policy: tool_policy,
          tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
          capabilities: llm_model.capabilities_overrides,
        )

      begin
        run_result =
          session.resume_with_tool_results(
            continuation: continuation,
            tool_results: tool_results,
            allow_partial: true,
            context: continuation.context_attributes,
          )

        begin
          ContinuationRecord.mark_consumed!(run_id: run_id, continuation_id: continuation_id, lock_token: lock_token)
        rescue ContinuationRecord::StaleContinuationError => e
          return Result.failure(errors: [e.message], code: "STALE_CONTINUATION", value: { run_id: run_id, continuation_id: continuation_id })
        end

        if run_result.respond_to?(:awaiting_tool_results?) && run_result.awaiting_tool_results?
          persisted_context_keys = continuation.context_attributes.keys

          continuation_payload =
            AgentCore::PromptRunner::ContinuationCodec.dump(
              run_result.continuation,
              context_keys: persisted_context_keys,
              include_traces: true,
            )

          ContinuationRecord.create!(
            run_id: run_result.run_id,
            continuation_id: continuation_payload.fetch("continuation_id"),
            parent_continuation_id: continuation_payload.fetch("parent_continuation_id", nil),
            llm_model: llm_model,
            tooling_key: tooling_key,
            status: "current",
            payload: continuation_payload,
          )

          task_payload =
            AgentCore::PromptRunner::ToolTaskCodec.dump(
              run_result.continuation,
              context_keys: persisted_context_keys,
            )

          enqueue_missing_tool_tasks!(task_payload, tooling_key: tooling_key)
        end

        Result.success(
          value: {
            run_result: run_result,
          },
        )
      rescue AgentCore::ProviderError, SimpleInference::Errors::Error => e
        begin
          ContinuationRecord.release_after_failure!(run_id: run_id, continuation_id: continuation_id, lock_token: lock_token, error: e)
        rescue ContinuationRecord::StaleContinuationError
        end
        Result.failure(errors: [e.message], code: "LLM_REQUEST_FAILED", value: { run_id: run_id })
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
        begin
          ContinuationRecord.release_after_failure!(run_id: run_id, continuation_id: continuation_id, lock_token: lock_token, error: e)
        rescue ContinuationRecord::StaleContinuationError
        end
        Result.failure(errors: [e.message], code: "INVALID_INPUT", value: { run_id: run_id })
      rescue StandardError => e
        begin
          ContinuationRecord.release_after_failure!(run_id: run_id, continuation_id: continuation_id, lock_token: lock_token, error: e)
        rescue ContinuationRecord::StaleContinuationError
        end
        raise
      end
    rescue AgentCore::ProviderError, SimpleInference::Errors::Error => e
      Result.failure(errors: [e.message], code: "LLM_REQUEST_FAILED", value: { run_id: run_id })
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
      Result.failure(errors: [e.message], code: "INVALID_INPUT", value: { run_id: run_id })
    end

    private

    attr_reader :run_id, :continuation_id, :client

    def effective_client(llm_model)
      client || llm_model.llm_provider.build_simple_inference_client
    end

    def resumeable_tool_call_ids(continuation)
      pending = Array(continuation.pending_tool_executions).map { |p| p.tool_call_id.to_s }.reject(&:empty?)

      buffered =
        if continuation.respond_to?(:buffered_tool_results) && continuation.buffered_tool_results.is_a?(Hash)
          continuation.buffered_tool_results.keys.map(&:to_s)
        else
          []
        end

      pending - buffered
    end

    def load_tool_results(run_id:, tool_call_ids:)
      ids = Array(tool_call_ids).map(&:to_s).reject(&:empty?).uniq
      return {} if ids.empty?

      ToolResultRecord
        .ready
        .where(run_id: run_id, tool_call_id: ids)
        .to_h do |r|
          [r.tool_call_id, AgentCore::Resources::Tools::ToolResult.from_h(r.tool_result)]
        end
    end

    def enqueue_missing_tool_tasks!(task_payload, tooling_key:)
      run_id = task_payload.fetch("run_id").to_s
      context_attributes = task_payload.fetch("context_attributes", {})
      tasks = Array(task_payload.fetch("tasks"))

      tasks.each do |t|
        tool_call_id = t.fetch("tool_call_id").to_s
        executed_name = t.fetch("executed_name").to_s

        _record, reserved =
          ToolResultRecord.reserve!(
            run_id: run_id,
            tool_call_id: tool_call_id,
            executed_name: executed_name,
          )

        next unless reserved

        LLM::ExecuteToolCallJob.perform_later(
          run_id: run_id,
          tooling_key: tooling_key,
          tool_call_id: tool_call_id,
          executed_name: executed_name,
          arguments: t.fetch("arguments"),
          context_attributes: context_attributes,
        )
      end
    end
  end
end
