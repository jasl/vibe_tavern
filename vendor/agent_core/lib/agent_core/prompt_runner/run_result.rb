# frozen_string_literal: true

module AgentCore
  module PromptRunner
    # The result of a complete agent run (potentially multiple turns).
    class RunResult
      attr_reader :messages, :final_message, :turns, :usage, :per_turn_usage, :tool_calls_made, :stop_reason

      # @param messages [Array<Message>] All messages from this run
      # @param final_message [Message] The last assistant message
      # @param turns [Integer] Number of LLM call turns
      # @param usage [Resources::Provider::Usage] Aggregated token usage
      # @param per_turn_usage [Array<Resources::Provider::Usage>] Per-turn token usage breakdown
      # @param tool_calls_made [Array<Hash>] Record of tool calls
      # @param stop_reason [Symbol] Why the run ended
      def initialize(messages:, final_message:, turns:, usage: nil, per_turn_usage: [], tool_calls_made: [], stop_reason: :end_turn)
        @messages = messages.freeze
        @final_message = final_message
        @turns = turns
        @usage = usage
        @per_turn_usage = per_turn_usage.freeze
        @tool_calls_made = tool_calls_made.freeze
        @stop_reason = stop_reason
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
    end
  end
end
