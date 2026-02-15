# frozen_string_literal: true

module AgentCore
  # Events emitted during streaming LLM responses and agent execution.
  #
  # Used by PromptRunner and Agent to communicate progress to callers.
  # Callers subscribe via block/callback and receive these events in real-time.
  #
  # @example Processing stream events
  #   agent.chat_stream("Hello") do |event|
  #     case event
  #     when StreamEvent::TextDelta
  #       print event.text
  #     when StreamEvent::ToolCallStart
  #       puts "Calling tool: #{event.name}"
  #     when StreamEvent::Done
  #       puts "\nFinished: #{event.stop_reason}"
  #     end
  #   end
  module StreamEvent
    # Text content being streamed from the LLM.
    class TextDelta
      attr_reader :text

      def initialize(text:)
        @text = text
      end

      def type = :text_delta
    end

    # Thinking/reasoning content being streamed.
    class ThinkingDelta
      attr_reader :text

      def initialize(text:)
        @text = text
      end

      def type = :thinking_delta
    end

    # A tool call has started.
    class ToolCallStart
      attr_reader :id, :name

      def initialize(id:, name:)
        @id = id
        @name = name
      end

      def type = :tool_call_start
    end

    # Partial tool call arguments being streamed.
    class ToolCallDelta
      attr_reader :id, :arguments_delta

      def initialize(id:, arguments_delta:)
        @id = id
        @arguments_delta = arguments_delta
      end

      def type = :tool_call_delta
    end

    # A tool call is complete (arguments fully received).
    class ToolCallEnd
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments:)
        @id = id
        @name = name
        args_hash = arguments.is_a?(Hash) ? arguments : {}
        @arguments = Utils.deep_stringify_keys(args_hash).freeze
      end

      def type = :tool_call_end
    end

    # Tool execution has started.
    class ToolExecutionStart
      attr_reader :tool_call_id, :name, :arguments

      def initialize(tool_call_id:, name:, arguments:)
        @tool_call_id = tool_call_id
        @name = name
        args_hash = arguments.is_a?(Hash) ? arguments : {}
        @arguments = Utils.deep_stringify_keys(args_hash).freeze
      end

      def type = :tool_execution_start
    end

    # Tool execution produced a partial result.
    class ToolExecutionUpdate
      attr_reader :tool_call_id, :partial_result

      def initialize(tool_call_id:, partial_result:)
        @tool_call_id = tool_call_id
        @partial_result = partial_result
      end

      def type = :tool_execution_update
    end

    # Tool execution has finished.
    class ToolExecutionEnd
      attr_reader :tool_call_id, :name, :result, :error

      def initialize(tool_call_id:, name:, result:, error: false)
        @tool_call_id = tool_call_id
        @name = name
        @result = result
        @error = !!error
      end

      def type = :tool_execution_end
      def error? = error
    end

    # The runner requires tool authorization/confirmation before continuing.
    #
    # Emitted by PromptRunner#run_stream when the tool policy returns
    # Decision.confirm for one or more tool calls.
    class AuthorizationRequired
      attr_reader :run_id, :pending_tool_confirmations

      def initialize(run_id:, pending_tool_confirmations:)
        @run_id = run_id.to_s
        @pending_tool_confirmations = Array(pending_tool_confirmations).freeze
      end

      def type = :authorization_required
    end

    # A new turn (LLM call) has started.
    class TurnStart
      attr_reader :turn_number

      def initialize(turn_number:)
        @turn_number = turn_number
      end

      def type = :turn_start
    end

    # A turn has ended.
    #
    # `stop_reason` / `usage` (when present) reflect the LLM call that produced
    # `message` for this turn.
    class TurnEnd
      attr_reader :turn_number, :message, :stop_reason, :usage

      def initialize(turn_number:, message:, stop_reason: nil, usage: nil)
        @turn_number = turn_number
        @message = message
        @stop_reason = stop_reason
        @usage = usage
      end

      def type = :turn_end
    end

    # The complete message has been received (end of an LLM stream).
    class MessageComplete
      attr_reader :message

      def initialize(message:)
        @message = message
      end

      def type = :message_complete
    end

    # The run has completed.
    #
    # When emitted by providers directly, this marks the end of the provider's
    # streaming response. When using PromptRunner#run_stream, Runner emits this
    # once for the entire tool loop (providers' per-call Done events are not
    # forwarded).
    class Done
      attr_reader :stop_reason, :usage

      def initialize(stop_reason:, usage: nil)
        @stop_reason = stop_reason
        @usage = usage
      end

      def type = :done
    end

    # An error occurred during streaming.
    class ErrorEvent
      attr_reader :error, :recoverable

      def initialize(error:, recoverable: false)
        @error = error
        @recoverable = recoverable
      end

      def type = :error
      def recoverable? = recoverable
    end
  end
end
