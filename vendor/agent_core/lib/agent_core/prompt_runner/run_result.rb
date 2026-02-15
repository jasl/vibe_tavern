# frozen_string_literal: true

module AgentCore
  module PromptRunner
    # Trace record for a single tool authorization decision.
    ToolAuthorizationTrace =
      Data.define(
        :tool_call_id,
        :name,
        :outcome,
        :reason,
        :duration_ms,
      )

    # Trace record for a single tool execution.
    ToolExecutionTrace =
      Data.define(
        :tool_call_id,
        :name,
        :executed_name,
        :source,
        :arguments_summary,
        :result_summary,
        :error,
        :duration_ms,
      ) do
        def error? = error == true
      end

    # Trace record for a single LLM call.
    LlmCallTrace =
      Data.define(
        :model,
        :messages_count,
        :tools_count,
        :options_summary,
        :stop_reason,
        :usage,
        :duration_ms,
      )

    # Trace record for one runner turn (one LLM call).
    TurnTrace =
      Data.define(
        :turn_number,
        :started_at,
        :ended_at,
        :duration_ms,
        :llm,
        :tool_authorizations,
        :tool_executions,
        :stop_reason,
        :usage,
      )

    # Trace record for the whole run.
    RunTrace =
      Data.define(
        :run_id,
        :started_at,
        :ended_at,
        :duration_ms,
        :turns,
        :stop_reason,
        :usage,
      )

    # A tool call awaiting explicit confirmation (pause/resume).
    PendingToolConfirmation =
      Data.define(
        :tool_call_id,
        :name,
        :arguments,
        :reason,
        :arguments_summary,
      )

    # Opaque continuation state for resuming a paused run.
    #
    # This object is intended to be treated as an implementation detail by
    # downstream apps. It is safe to persist only if the app explicitly
    # serializes it (AgentCore does not guarantee JSON-compatibility for all
    # embedded values by default).
    Continuation =
      Data.define(
        :run_id,
        :started_at,
        :duration_ms,
        :turn,
        :max_turns,
        :messages,
        :model,
        :options,
        :tools,
        :tools_enabled,
        :empty_final_fixup_attempted,
        :any_tool_calls_seen,
        :tool_calls_record,
        :aggregated_usage,
        :per_turn_usage,
        :turn_traces,
        :pending_tool_calls,
        :pending_decisions,
        :context_attributes,
        :max_tool_output_bytes,
        :max_tool_calls_per_turn,
        :fix_empty_final,
        :fix_empty_final_user_text,
        :fix_empty_final_disable_tools,
      )

    # The result of a complete agent run (potentially multiple turns).
    class RunResult
      attr_reader :run_id, :started_at, :ended_at, :duration_ms,
                  :messages, :final_message, :turns, :usage, :per_turn_usage,
                  :tool_calls_made, :stop_reason, :trace,
                  :pending_tool_confirmations, :continuation

      # @param messages [Array<Message>] All messages from this run
      # @param final_message [Message] The last assistant message
      # @param turns [Integer] Number of LLM call turns
      # @param usage [Resources::Provider::Usage] Aggregated token usage
      # @param per_turn_usage [Array<Resources::Provider::Usage>] Per-turn token usage breakdown
      # @param tool_calls_made [Array<Hash>] Record of tool calls
      # @param stop_reason [Symbol] Why the run ended
      # @param trace [RunTrace, nil] Structured trace summary (safe for audits)
      # @param pending_tool_confirmations [Array<PendingToolConfirmation, Hash>] Pending tool calls requiring confirmation (when paused)
      # @param continuation [Object, nil] Resume token/state (when paused)
      def initialize(
        run_id:,
        started_at:,
        ended_at:,
        duration_ms:,
        messages:,
        final_message:,
        turns:,
        usage: nil,
        per_turn_usage: [],
        tool_calls_made: [],
        stop_reason: :end_turn,
        trace: nil,
        pending_tool_confirmations: [],
        continuation: nil
      )
        @run_id = run_id.to_s.freeze
        @started_at = started_at
        @ended_at = ended_at
        @duration_ms = duration_ms
        @messages = messages.freeze
        @final_message = final_message
        @turns = turns
        @usage = usage
        @per_turn_usage = per_turn_usage.freeze
        @tool_calls_made = tool_calls_made.freeze
        @stop_reason = stop_reason
        @trace = trace
        @pending_tool_confirmations = Array(pending_tool_confirmations).freeze
        @continuation = continuation
      end

      # The text of the final assistant message.
      def text
        final_message&.text
      end

      # Whether any tools were called during this run.
      def used_tools?
        tool_calls_made.any?
      end

      # Whether the run was terminated due to max turns.
      def max_turns_reached?
        stop_reason == :max_turns
      end

      def awaiting_tool_confirmation?
        stop_reason == :awaiting_tool_confirmation
      end
    end
  end
end
