# frozen_string_literal: true

module AgentCore
  module PromptRunner
    # Executes prompts against an LLM provider with tool-calling loop.
    #
    # The runner is the core execution engine. It:
    # 1. Sends the prompt to the LLM
    # 2. If the response contains tool calls → executes them → appends results → loops
    # 3. Repeats until the LLM returns a final text response or max_turns is reached
    #
    # The runner is stateless and re-entrant. It receives all dependencies as
    # arguments and does not hold mutable state between calls.
    #
    # @example Sync execution
    #   runner = AgentCore::PromptRunner::Runner.new
    #   result = runner.run(
    #     prompt: built_prompt,
    #     provider: my_provider,
    #     tools_registry: registry,
    #     max_turns: 10
    #   )
    #   puts result.text
    #
    # @example Streaming execution
    #   runner.run_stream(prompt: built_prompt, provider: my_provider, tools_registry: registry) do |event|
    #     case event
    #     when StreamEvent::TextDelta then print event.text
    #     when StreamEvent::Done then puts "\nDone!"
    #     end
    #   end
    class Runner
      DEFAULT_MAX_TURNS = 10

      # Run a prompt to completion (synchronous).
      #
      # @param prompt [PromptBuilder::BuiltPrompt] The built prompt
      # @param provider [Resources::Provider::Base] LLM provider
      # @param tools_registry [Resources::Tools::Registry, nil] Tool registry
      # @param tool_policy [Resources::Tools::Policy::Base, nil] Tool policy
      # @param max_turns [Integer] Maximum tool-calling turns
      # @param events [Events, nil] Event callbacks
      # @return [RunResult]
      def run(prompt:, provider:, tools_registry: nil, tool_policy: nil, max_turns: DEFAULT_MAX_TURNS, events: nil,
              token_counter: nil, context_window: nil, reserved_output_tokens: 0)
        raise ArgumentError, "max_turns must be >= 1, got #{max_turns}" if max_turns < 1

        events ||= Events.new
        messages = prompt.messages.dup
        apply_system_prompt!(prompt.system_prompt, messages)
        all_new_messages = []
        tool_calls_record = []
        aggregated_usage = nil
        per_turn_usage = []
        options = Utils.symbolize_keys(prompt.options)
        model = options.delete(:model)
        turn = 0

        loop do
          turn += 1

          if turn > max_turns
            events.emit(:error, MaxTurnsExceededError.new(turns: max_turns), false)
            return build_result(
              all_new_messages: all_new_messages,
              turns: turn - 1,
              usage: aggregated_usage,
              tool_calls_record: tool_calls_record,
              stop_reason: :max_turns,
              per_turn_usage: per_turn_usage
            )
          end

          events.emit(:turn_start, turn)

          # Build LLM request
          tools = prompt.has_tools? ? prompt.tools : nil
          request_messages = messages.dup.freeze

          # Preflight token check
          begin
            preflight_token_check!(
              messages: request_messages, tools: tools,
              token_counter: token_counter, context_window: context_window,
              reserved_output_tokens: reserved_output_tokens
            )
          rescue ContextWindowExceededError => e
            events.emit(:error, e, false)
            raise
          end

          events.emit(:llm_request, request_messages, tools)

          # Call LLM
          response = provider.chat(
            messages: request_messages,
            model: model,
            tools: tools,
            stream: false,
            **options
          )

          events.emit(:llm_response, response)

          # Track usage
          if response.usage
            per_turn_usage << response.usage
            aggregated_usage = aggregated_usage ? aggregated_usage + response.usage : response.usage
          end

          # Add assistant message to conversation
          assistant_msg = response.message
          unless assistant_msg
            events.emit(:error, ProviderError.new("Provider returned nil message"), false)
            return build_result(
              all_new_messages: all_new_messages,
              turns: turn,
              usage: aggregated_usage,
              tool_calls_record: tool_calls_record,
              stop_reason: :error,
              per_turn_usage: per_turn_usage
            )
          end

          messages << assistant_msg
          all_new_messages << assistant_msg

          # Check if we need to execute tool calls
          if response.has_tool_calls? && tools_registry
            tool_results = execute_tool_calls(
              tool_calls: response.tool_calls,
              tools_registry: tools_registry,
              tool_policy: tool_policy,
              events: events,
              tool_calls_record: tool_calls_record,
              stream_block: nil
            )

            # Add tool results to conversation
            tool_results.each do |result_msg|
              messages << result_msg
              all_new_messages << result_msg
            end

            events.emit(:turn_end, turn, all_new_messages)
            # Continue loop for next LLM call with tool results
          else
            # No tool calls — this is the final response
            events.emit(:turn_end, turn, all_new_messages)
            return build_result(
              all_new_messages: all_new_messages,
              turns: turn,
              usage: aggregated_usage,
              tool_calls_record: tool_calls_record,
              stop_reason: response.stop_reason || :end_turn,
              per_turn_usage: per_turn_usage
            )
          end
        end
      end

      # Run a prompt with streaming (yields StreamEvent objects).
      #
      # @param prompt [PromptBuilder::BuiltPrompt] The built prompt
      # @param provider [Resources::Provider::Base] LLM provider
      # @param tools_registry [Resources::Tools::Registry, nil] Tool registry
      # @param tool_policy [Resources::Tools::Policy::Base, nil] Tool policy
      # @param max_turns [Integer] Maximum turns
      # @param events [Events, nil] Event callbacks
      # @yield [StreamEvent] Stream events
      # @return [RunResult]
      def run_stream(prompt:, provider:, tools_registry: nil, tool_policy: nil, max_turns: DEFAULT_MAX_TURNS, events: nil,
                     token_counter: nil, context_window: nil, reserved_output_tokens: 0, &block)
        raise ArgumentError, "max_turns must be >= 1, got #{max_turns}" if max_turns < 1

        events ||= Events.new
        messages = prompt.messages.dup
        apply_system_prompt!(prompt.system_prompt, messages)
        all_new_messages = []
        tool_calls_record = []
        aggregated_usage = nil
        per_turn_usage = []
        options = Utils.symbolize_keys(prompt.options)
        model = options.delete(:model)
        turn = 0

        loop do
          turn += 1

          if turn > max_turns
            yield StreamEvent::ErrorEvent.new(error: "Max turns exceeded", recoverable: false) if block
            return build_result(
              all_new_messages: all_new_messages,
              turns: turn - 1,
              usage: aggregated_usage,
              tool_calls_record: tool_calls_record,
              stop_reason: :max_turns,
              per_turn_usage: per_turn_usage
            )
          end

          yield StreamEvent::TurnStart.new(turn_number: turn) if block
          events.emit(:turn_start, turn)

          tools = prompt.has_tools? ? prompt.tools : nil
          request_messages = messages.dup.freeze

          # Preflight token check
          begin
            preflight_token_check!(
              messages: request_messages, tools: tools,
              token_counter: token_counter, context_window: context_window,
              reserved_output_tokens: reserved_output_tokens
            )
          rescue ContextWindowExceededError => e
            yield StreamEvent::ErrorEvent.new(error: e.message, recoverable: false) if block
            events.emit(:error, e, false)
            raise
          end

          events.emit(:llm_request, request_messages, tools)

          # Stream LLM response
          stream_enum = provider.chat(
            messages: request_messages,
            model: model,
            tools: tools,
            stream: true,
            **options
          )

          # Collect the response from stream events
          assistant_msg = nil
          response_stop_reason = :end_turn
          response_usage = nil

          stream_enum.each do |event|
            # Forward stream events to caller
            yield event if block
            events.emit(:stream_delta, event)

            case event
            when StreamEvent::Done
              response_stop_reason = event.stop_reason
              response_usage = event.usage
            when StreamEvent::MessageComplete
              assistant_msg = event.message
            end
          end

          # Track usage
          if response_usage
            per_turn_usage << response_usage
            aggregated_usage = aggregated_usage ? aggregated_usage + response_usage : response_usage
          end

          # If we didn't get a MessageComplete from the provider stream,
          # something went wrong — we can't continue the conversation.
          unless assistant_msg
            yield StreamEvent::ErrorEvent.new(
              error: "Provider stream ended without producing a MessageComplete event",
              recoverable: false
            ) if block
            return build_result(
              all_new_messages: all_new_messages,
              turns: turn,
              usage: aggregated_usage,
              tool_calls_record: tool_calls_record,
              stop_reason: :error,
              per_turn_usage: per_turn_usage
            )
          end

          messages << assistant_msg
          all_new_messages << assistant_msg
          events.emit(
            :llm_response,
            Resources::Provider::Response.new(
              message: assistant_msg,
              usage: response_usage,
              stop_reason: response_stop_reason
            )
          )

          # Handle tool calls
          if assistant_msg&.has_tool_calls? && tools_registry
            tool_results = execute_tool_calls(
              tool_calls: assistant_msg.tool_calls,
              tools_registry: tools_registry,
              tool_policy: tool_policy,
              events: events,
              tool_calls_record: tool_calls_record,
              stream_block: block
            )

            tool_results.each do |result_msg|
              messages << result_msg
              all_new_messages << result_msg
            end

            yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg) if block
            events.emit(:turn_end, turn, all_new_messages)
          else
            yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg) if block
            events.emit(:turn_end, turn, all_new_messages)

            yield StreamEvent::Done.new(stop_reason: response_stop_reason, usage: aggregated_usage) if block

            return build_result(
              all_new_messages: all_new_messages,
              turns: turn,
              usage: aggregated_usage,
              tool_calls_record: tool_calls_record,
              stop_reason: response_stop_reason,
              per_turn_usage: per_turn_usage
            )
          end
        end
      end

      private

      # Execute tool calls, optionally emitting stream events.
      # Unified implementation for both sync and streaming modes.
      def execute_tool_calls(tool_calls:, tools_registry:, tool_policy:, events:, tool_calls_record:, stream_block: nil)
        tool_calls.map do |tc|
          stream_block&.call(StreamEvent::ToolExecutionStart.new(
            tool_call_id: tc.id, name: tc.name, arguments: tc.arguments
          ))
          events.emit(:tool_call, tc.name, tc.arguments, tc.id)

          # Check policy
          if tool_policy
            decision = tool_policy.authorize(name: tc.name, arguments: tc.arguments)
            unless decision.allowed?
              error_result = Resources::Tools::ToolResult.error(
                text: "Tool call denied: #{decision.reason}"
              )
              stream_block&.call(StreamEvent::ToolExecutionEnd.new(
                tool_call_id: tc.id, name: tc.name, result: error_result, is_error: true
              ))
              events.emit(:tool_result, tc.name, error_result, tc.id)
              tool_calls_record << { name: tc.name, arguments: tc.arguments, error: decision.reason }

              next Message.new(
                role: :tool_result, content: error_result.text,
                tool_call_id: tc.id, name: tc.name
              )
            end
          end

          # Execute tool
          result = begin
            tools_registry.execute(name: tc.name, arguments: tc.arguments)
          rescue ToolNotFoundError => e
            Resources::Tools::ToolResult.error(text: e.message)
          rescue => e
            Resources::Tools::ToolResult.error(text: "Tool '#{tc.name}' raised: #{e.message}")
          end
          stream_block&.call(StreamEvent::ToolExecutionEnd.new(
            tool_call_id: tc.id, name: tc.name, result: result, is_error: result.error?
          ))
          events.emit(:tool_result, tc.name, result, tc.id)
          tool_calls_record << {
            name: tc.name, arguments: tc.arguments,
            error: result.error? ? result.text : nil,
          }

          Message.new(
            role: :tool_result, content: result.text,
            tool_call_id: tc.id, name: tc.name,
            metadata: { is_error: result.error? }
          )
        end
      end

      def build_result(all_new_messages:, turns:, usage:, tool_calls_record:, stop_reason:, per_turn_usage: [])
        final = all_new_messages.reverse.find { |m| m.assistant? } || all_new_messages.last

        RunResult.new(
          messages: all_new_messages,
          final_message: final,
          turns: turns,
          usage: usage,
          tool_calls_made: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage
        )
      end

      # Raise ContextWindowExceededError if estimated tokens exceed the limit.
      # No-op when token_counter or context_window is nil (opt-in).
      def preflight_token_check!(messages:, tools:, token_counter:, context_window:, reserved_output_tokens:)
        return unless token_counter && context_window

        unless context_window.is_a?(Integer) && context_window.positive?
          raise ArgumentError, "context_window must be a positive Integer (got #{context_window.inspect})"
        end

        unless reserved_output_tokens.is_a?(Integer) && reserved_output_tokens >= 0
          raise ArgumentError, "reserved_output_tokens must be a non-negative Integer (got #{reserved_output_tokens.inspect})"
        end

        if reserved_output_tokens >= context_window
          raise ArgumentError, "reserved_output_tokens must be less than context_window " \
                               "(got reserved_output_tokens=#{reserved_output_tokens}, context_window=#{context_window})"
        end

        msg_tokens = token_counter.count_messages(messages)
        tool_tokens = tools ? token_counter.count_tools(tools) : 0
        estimated = msg_tokens + tool_tokens
        limit = context_window - reserved_output_tokens

        return if estimated <= limit

        raise ContextWindowExceededError.new(
          estimated_tokens: estimated,
          message_tokens: msg_tokens,
          tool_tokens: tool_tokens,
          context_window: context_window,
          reserved_output: reserved_output_tokens,
          limit: limit
        )
      end

      def apply_system_prompt!(system_prompt, messages)
        system_text = system_prompt.to_s
        return messages if system_text.empty?

        system_message = Message.new(role: :system, content: system_text.dup)

        if messages.first&.system?
          messages[0] = system_message unless messages.first.text == system_text
        else
          messages.unshift(system_message)
        end

        messages
      end
    end
  end
end
