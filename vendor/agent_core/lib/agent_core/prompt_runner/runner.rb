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
      DEFAULT_FIX_EMPTY_FINAL_USER_TEXT = "Please provide your final answer."

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
              token_counter: nil, context_window: nil, reserved_output_tokens: 0,
              context: nil, instrumenter: nil,
              fix_empty_final: true, fix_empty_final_user_text: DEFAULT_FIX_EMPTY_FINAL_USER_TEXT,
              fix_empty_final_disable_tools: true, max_tool_output_bytes: Utils::DEFAULT_MAX_TOOL_OUTPUT_BYTES,
              max_tool_calls_per_turn: nil, tool_executor: ToolExecutor::Inline.new)
        raise ArgumentError, "max_turns must be >= 1, got #{max_turns}" if max_turns < 1

        max_tool_output_bytes = Integer(max_tool_output_bytes)
        raise ArgumentError, "max_tool_output_bytes must be positive" if max_tool_output_bytes <= 0

        fix_empty_final_user_text = fix_empty_final_user_text.to_s
        fix_empty_final_user_text = DEFAULT_FIX_EMPTY_FINAL_USER_TEXT if fix_empty_final_user_text.strip.empty?

        events ||= Events.new
        execution_context = ExecutionContext.from(context, instrumenter: instrumenter)
        instrumenter = execution_context.instrumenter
        clock = execution_context.clock
        run_id = execution_context.run_id

        messages = prompt.messages.dup
        apply_system_prompt!(prompt.system_prompt, messages)

        all_new_messages = []
        tool_calls_record = []
        aggregated_usage = nil
        per_turn_usage = []
        turn_traces = []
        pending_tool_confirmations = []
        pending_tool_executions = []
        continuation = nil
        pause_state = nil

        options = Utils.symbolize_keys(prompt.options)
        model = options.delete(:model)

        turn = 0
        tools_enabled = true
        empty_final_fixup_attempted = false
        any_tool_calls_seen = false

        run_started_at = clock.now
        run_started_mono = clock.monotonic
        stop_reason = :end_turn
        completed_turns = 0

        run_payload = { run_id: run_id }

        instrumenter.instrument("agent_core.run", run_payload) do
          begin
            loop do
              turn += 1

              if turn > max_turns
                completed_turns = turn - 1
                stop_reason = :max_turns
                run_payload[:stop_reason] = stop_reason
                events.emit(:error, MaxTurnsExceededError.new(turns: max_turns), false)
                break
              end

              turn_started_at = clock.now
              turn_payload = { run_id: run_id, turn_number: turn }

              tool_authorization_traces = []
              tool_execution_traces = []
              llm_trace = nil
              turn_stop_reason = :end_turn
              turn_usage_obj = nil

              turn_outcome =
                instrumenter.instrument("agent_core.turn", turn_payload) do
                  begin
                    events.emit(:turn_start, turn)

                    tools = tools_enabled && prompt.has_tools? ? prompt.tools : nil
                    request_messages = messages.dup.freeze

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

                    llm_payload = {
                      run_id: run_id,
                      turn_number: turn,
                      model: model,
                      stream: false,
                      messages_count: request_messages.size,
                      tools_count: tools ? tools.size : 0,
                      options_summary: summarize_llm_options(options),
                    }

                    response =
                      instrumenter.instrument("agent_core.llm.call", llm_payload) do
                        resp =
                          provider.chat(
                            messages: request_messages,
                            model: model,
                            tools: tools,
                            stream: false,
                            **options
                          )
                        llm_payload[:stop_reason] = resp.stop_reason
                        llm_payload[:usage] = resp.usage&.to_h
                        resp
                      end

                    events.emit(:llm_response, response)

                    llm_trace =
                      LlmCallTrace.new(
                        model: model.to_s,
                        messages_count: request_messages.size,
                        tools_count: tools ? tools.size : 0,
                        options_summary: llm_payload.fetch(:options_summary),
                        stop_reason: llm_payload.fetch(:stop_reason, nil),
                        usage: llm_payload.fetch(:usage, nil),
                        duration_ms: llm_payload.fetch(:duration_ms, nil),
                      )

                    turn_usage_obj = response.usage
                    turn_stop_reason = response.stop_reason || :end_turn

                    if response.usage
                      per_turn_usage << response.usage
                      aggregated_usage = aggregated_usage ? aggregated_usage + response.usage : response.usage
                    end

                    assistant_msg = response.message
                    unless assistant_msg
                      events.emit(:error, ProviderError.new("Provider returned nil message"), false)
                      stop_reason = :error
                      completed_turns = turn
                      run_payload[:stop_reason] = stop_reason
                      events.emit(:turn_end, turn, all_new_messages)
                      next :stop
                    end

                    tool_calls = assistant_msg.tool_calls || []

                    effective_max_tool_calls_per_turn =
                      if max_tool_calls_per_turn
                        limit = Integer(max_tool_calls_per_turn)
                        raise ArgumentError, "max_tool_calls_per_turn must be positive" if limit <= 0
                        limit
                      elsif options.fetch(:parallel_tool_calls, nil) == false
                        1
                      end

                    if tools_registry && tools && effective_max_tool_calls_per_turn && tool_calls.size > effective_max_tool_calls_per_turn
                      ignored = tool_calls.drop(effective_max_tool_calls_per_turn)

                      ignored.each do |tc|
                        tool_calls_record << {
                          name: tc.name,
                          arguments: tc.arguments,
                          error: "ignored: max_tool_calls_per_turn=#{effective_max_tool_calls_per_turn}",
                        }
                      end

                      tool_calls = tool_calls.first(effective_max_tool_calls_per_turn)

                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: tool_calls.empty? ? nil : tool_calls,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                    elsif tools.nil? && assistant_msg.has_tool_calls?
                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: nil,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                      tool_calls = []
                    end

                    messages << assistant_msg
                    all_new_messages << assistant_msg

                    any_tool_calls_seen ||= tool_calls.any? if tools_registry && tools

                    if tool_calls.any? && tools_registry && tools
                      tool_processing =
                        process_tool_calls_for_turn(
                          tool_calls: tool_calls,
                          tools_registry: tools_registry,
                          tool_policy: tool_policy,
                          tool_executor: tool_executor,
                          events: events,
                          tool_calls_record: tool_calls_record,
                          max_tool_output_bytes: max_tool_output_bytes,
                          turn_number: turn,
                          execution_context: execution_context,
                          stream_block: nil
                        )

                      tool_authorization_traces.concat(tool_processing.fetch(:authorization_traces))
                      tool_execution_traces.concat(tool_processing.fetch(:execution_traces))

                      Array(tool_processing[:result_messages]).each do |result_msg|
                        messages << result_msg
                        all_new_messages << result_msg
                      end

                      if tool_processing[:pause_state]
                        pause_state = tool_processing.fetch(:pause_state)
                        stop_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
                        turn_stop_reason = stop_reason
                        completed_turns = turn
                        run_payload[:stop_reason] = stop_reason
                        publish_pause_event(
                          instrumenter,
                          run_id: run_id,
                          turn_number: turn,
                          pause_state: pause_state,
                          parent_continuation_id: continuation&.continuation_id,
                        )
                        events.emit(:turn_end, turn, all_new_messages)
                        next :stop
                      end

                      events.emit(:turn_end, turn, all_new_messages)
                      next :continue
                    end

                    if fix_empty_final &&
                        !empty_final_fixup_attempted &&
                        tools_registry &&
                        any_tool_calls_seen &&
                        assistant_msg.assistant? &&
                        assistant_msg.text.to_s.strip.empty?
                      empty_final_fixup_attempted = true
                      tools_enabled = false if fix_empty_final_disable_tools
                      events.emit(:turn_end, turn, all_new_messages)
                      user_msg = Message.new(role: :user, content: fix_empty_final_user_text)
                      messages << user_msg
                      all_new_messages << user_msg
                      next :continue
                    end

                    events.emit(:turn_end, turn, all_new_messages)
                    stop_reason = turn_stop_reason
                    completed_turns = turn
                    run_payload[:stop_reason] = stop_reason
                    :stop
                  ensure
                    turn_payload[:stop_reason] ||= turn_stop_reason
                    turn_payload[:usage] ||= turn_usage_obj&.to_h if turn_usage_obj
                  end
                end

              turn_ended_at = clock.now

              turn_traces <<
                TurnTrace.new(
                  turn_number: turn,
                  started_at: turn_started_at,
                  ended_at: turn_ended_at,
                  duration_ms: turn_payload.fetch(:duration_ms, nil),
                  llm: llm_trace,
                  tool_authorizations: tool_authorization_traces,
                  tool_executions: tool_execution_traces,
                  stop_reason: turn_stop_reason,
                  usage: turn_usage_obj&.to_h,
                )

              break if turn_outcome == :stop
            end
          ensure
            run_payload[:turns] ||= completed_turns
            run_payload[:usage] ||= aggregated_usage&.to_h if aggregated_usage
          end
        end

        run_ended_at = clock.now
        run_duration_ms = (clock.monotonic - run_started_mono) * 1000.0

        run_trace =
          RunTrace.new(
            run_id: run_id,
            started_at: run_started_at,
            ended_at: run_ended_at,
            duration_ms: run_duration_ms,
            turns: turn_traces,
            stop_reason: stop_reason,
            usage: aggregated_usage&.to_h,
          )

        if pause_state
          ensure_pause_state_ids!(pause_state)

          pause_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
          pending_tool_confirmations =
            pause_reason == :awaiting_tool_confirmation ? pause_state.fetch(:pending_tool_confirmations) : []
          pending_tool_executions =
            pause_reason == :awaiting_tool_results ? pause_state.fetch(:pending_tool_executions) : []

          continuation =
            Continuation.new(
              run_id: run_id,
              continuation_id: normalize_optional_id(pause_state[:continuation_id]),
              parent_continuation_id: normalize_optional_id(pause_state[:parent_continuation_id]),
              started_at: run_started_at,
              duration_ms: run_duration_ms,
              turn: completed_turns,
              max_turns: max_turns,
              messages: messages.dup.freeze,
              model: model,
              options: options.dup.freeze,
              tools: prompt.tools,
              tools_enabled: tools_enabled,
              empty_final_fixup_attempted: empty_final_fixup_attempted,
              any_tool_calls_seen: any_tool_calls_seen,
              tool_calls_record: tool_calls_record.dup.freeze,
              aggregated_usage: aggregated_usage,
              per_turn_usage: per_turn_usage.dup.freeze,
              turn_traces: turn_traces.dup.freeze,
              pause_reason: pause_reason,
              pending_tool_calls: pause_state.fetch(:pending_tool_calls),
              pending_tool_executions: pending_tool_executions,
              buffered_tool_results: buffered_tool_results_for(pause_state),
              pending_decisions: pause_state.fetch(:pending_decisions),
              context_attributes: execution_context.attributes,
              max_tool_output_bytes: max_tool_output_bytes,
              max_tool_calls_per_turn: max_tool_calls_per_turn,
              fix_empty_final: fix_empty_final,
              fix_empty_final_user_text: fix_empty_final_user_text,
              fix_empty_final_disable_tools: fix_empty_final_disable_tools,
            )
        end

        build_result(
          run_id: run_id,
          started_at: run_started_at,
          ended_at: run_ended_at,
          duration_ms: run_duration_ms,
          trace: run_trace,
          all_new_messages: all_new_messages,
          turns: completed_turns,
          usage: aggregated_usage,
          tool_calls_record: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage,
          pending_tool_confirmations: pending_tool_confirmations,
          pending_tool_executions: pending_tool_executions,
          continuation: continuation
        )
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
                     token_counter: nil, context_window: nil, reserved_output_tokens: 0,
                     context: nil, instrumenter: nil,
                     fix_empty_final: true, fix_empty_final_user_text: DEFAULT_FIX_EMPTY_FINAL_USER_TEXT,
                     fix_empty_final_disable_tools: true, max_tool_output_bytes: Utils::DEFAULT_MAX_TOOL_OUTPUT_BYTES,
                     max_tool_calls_per_turn: nil, tool_executor: ToolExecutor::Inline.new, &block)
        raise ArgumentError, "max_turns must be >= 1, got #{max_turns}" if max_turns < 1

        max_tool_output_bytes = Integer(max_tool_output_bytes)
        raise ArgumentError, "max_tool_output_bytes must be positive" if max_tool_output_bytes <= 0

        fix_empty_final_user_text = fix_empty_final_user_text.to_s
        fix_empty_final_user_text = DEFAULT_FIX_EMPTY_FINAL_USER_TEXT if fix_empty_final_user_text.strip.empty?

        events ||= Events.new
        execution_context = ExecutionContext.from(context, instrumenter: instrumenter)
        instrumenter = execution_context.instrumenter
        clock = execution_context.clock
        run_id = execution_context.run_id

        messages = prompt.messages.dup
        apply_system_prompt!(prompt.system_prompt, messages)

        all_new_messages = []
        tool_calls_record = []
        aggregated_usage = nil
        per_turn_usage = []
        turn_traces = []
        pending_tool_confirmations = []
        pending_tool_executions = []
        continuation = nil
        pause_state = nil

        options = Utils.symbolize_keys(prompt.options)
        model = options.delete(:model)

        turn = 0
        tools_enabled = true
        empty_final_fixup_attempted = false
        any_tool_calls_seen = false

        run_started_at = clock.now
        run_started_mono = clock.monotonic
        stop_reason = :end_turn
        completed_turns = 0

        run_payload = { run_id: run_id }

        instrumenter.instrument("agent_core.run", run_payload) do
          begin
            loop do
              turn += 1

              if turn > max_turns
                completed_turns = turn - 1
                stop_reason = :max_turns
                run_payload[:stop_reason] = stop_reason
                yield StreamEvent::ErrorEvent.new(error: "Max turns exceeded", recoverable: false) if block
                break
              end

              yield StreamEvent::TurnStart.new(turn_number: turn) if block
              events.emit(:turn_start, turn)

              turn_started_at = clock.now
              turn_payload = { run_id: run_id, turn_number: turn }

              tool_authorization_traces = []
              tool_execution_traces = []
              llm_trace = nil
              turn_stop_reason = :end_turn
              turn_usage_obj = nil

              turn_outcome =
                instrumenter.instrument("agent_core.turn", turn_payload) do
                  begin
                    tools = tools_enabled && prompt.has_tools? ? prompt.tools : nil
                    request_messages = messages.dup.freeze

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

                    assistant_msg = nil
                    response_stop_reason = :end_turn
                    response_usage = nil

                    llm_payload = {
                      run_id: run_id,
                      turn_number: turn,
                      model: model,
                      stream: true,
                      messages_count: request_messages.size,
                      tools_count: tools ? tools.size : 0,
                      options_summary: summarize_llm_options(options),
                    }

                    instrumenter.instrument("agent_core.llm.call", llm_payload) do
                      stream_enum =
                        provider.chat(
                          messages: request_messages,
                          model: model,
                          tools: tools,
                          stream: true,
                          **options
                        )

                      stream_enum.each do |event|
                        events.emit(:stream_delta, event)

                        case event
                        when StreamEvent::Done
                          response_stop_reason = event.stop_reason
                          response_usage = event.usage
                          next
                        when StreamEvent::MessageComplete
                          assistant_msg = event.message
                        end

                        yield event if block
                      end

                      llm_payload[:stop_reason] = response_stop_reason
                      llm_payload[:usage] = response_usage&.to_h

                      nil
                    end

                    llm_trace =
                      LlmCallTrace.new(
                        model: model.to_s,
                        messages_count: request_messages.size,
                        tools_count: tools ? tools.size : 0,
                        options_summary: llm_payload.fetch(:options_summary),
                        stop_reason: llm_payload.fetch(:stop_reason, nil),
                        usage: llm_payload.fetch(:usage, nil),
                        duration_ms: llm_payload.fetch(:duration_ms, nil),
                      )

                    turn_usage_obj = response_usage
                    turn_stop_reason = response_stop_reason

                    if response_usage
                      per_turn_usage << response_usage
                      aggregated_usage = aggregated_usage ? aggregated_usage + response_usage : response_usage
                    end

                    unless assistant_msg
                      yield StreamEvent::ErrorEvent.new(
                        error: "Provider stream ended without producing a MessageComplete event",
                        recoverable: false
                      ) if block
                      stop_reason = :error
                      completed_turns = turn
                      run_payload[:stop_reason] = stop_reason
                      events.emit(:turn_end, turn, all_new_messages)
                      next :stop
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

                    effective_max_tool_calls_per_turn =
                      if max_tool_calls_per_turn
                        limit = Integer(max_tool_calls_per_turn)
                        raise ArgumentError, "max_tool_calls_per_turn must be positive" if limit <= 0
                        limit
                      elsif options.fetch(:parallel_tool_calls, nil) == false
                        1
                      end

                    tool_calls = assistant_msg.tool_calls || []

                    if tools_registry && tools && effective_max_tool_calls_per_turn && tool_calls.size > effective_max_tool_calls_per_turn
                      ignored = tool_calls.drop(effective_max_tool_calls_per_turn)

                      ignored.each do |tc|
                        tool_calls_record << {
                          name: tc.name,
                          arguments: tc.arguments,
                          error: "ignored: max_tool_calls_per_turn=#{effective_max_tool_calls_per_turn}",
                        }
                      end

                      tool_calls = tool_calls.first(effective_max_tool_calls_per_turn)

                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: tool_calls.empty? ? nil : tool_calls,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                      messages[-1] = assistant_msg
                      all_new_messages[-1] = assistant_msg
                    elsif tools.nil? && assistant_msg.has_tool_calls?
                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: nil,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                      tool_calls = []
                      messages[-1] = assistant_msg
                      all_new_messages[-1] = assistant_msg
                    end

                    any_tool_calls_seen ||= tool_calls.any? if tools_registry && tools

                    if tool_calls.any? && tools_registry && tools
                      tool_processing =
                        process_tool_calls_for_turn(
                          tool_calls: tool_calls,
                          tools_registry: tools_registry,
                          tool_policy: tool_policy,
                          tool_executor: tool_executor,
                          events: events,
                          tool_calls_record: tool_calls_record,
                          max_tool_output_bytes: max_tool_output_bytes,
                          turn_number: turn,
                          execution_context: execution_context,
                          stream_block: block
                        )

                      tool_authorization_traces.concat(tool_processing.fetch(:authorization_traces))
                      tool_execution_traces.concat(tool_processing.fetch(:execution_traces))

                      Array(tool_processing[:result_messages]).each do |result_msg|
                        messages << result_msg
                        all_new_messages << result_msg
                      end

                      yield StreamEvent::TurnEnd.new(
                        turn_number: turn,
                        message: assistant_msg,
                        stop_reason: response_stop_reason,
                        usage: response_usage
                      ) if block
                      events.emit(:turn_end, turn, all_new_messages)

                      if tool_processing[:pause_state]
                        pause_state = tool_processing.fetch(:pause_state)
                        stop_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
                        turn_stop_reason = stop_reason
                        completed_turns = turn
                        run_payload[:stop_reason] = stop_reason
                        publish_pause_event(
                          instrumenter,
                          run_id: run_id,
                          turn_number: turn,
                          pause_state: pause_state,
                          parent_continuation_id: continuation&.continuation_id,
                        )

                        case stop_reason
                        when :awaiting_tool_confirmation
                          yield StreamEvent::AuthorizationRequired.new(
                            run_id: run_id,
                            pending_tool_confirmations: pause_state.fetch(:pending_tool_confirmations),
                          ) if block
                        when :awaiting_tool_results
                          yield StreamEvent::ToolExecutionRequired.new(
                            run_id: run_id,
                            pending_tool_executions: pause_state.fetch(:pending_tool_executions),
                          ) if block
                        end
                        next :stop
                      end

                      next :continue
                    end

                    if fix_empty_final &&
                        !empty_final_fixup_attempted &&
                        tools_registry &&
                        any_tool_calls_seen &&
                        assistant_msg.assistant? &&
                        assistant_msg.text.to_s.strip.empty?
                      empty_final_fixup_attempted = true
                      tools_enabled = false if fix_empty_final_disable_tools
                      yield StreamEvent::TurnEnd.new(
                        turn_number: turn,
                        message: assistant_msg,
                        stop_reason: response_stop_reason,
                        usage: response_usage
                      ) if block
                      events.emit(:turn_end, turn, all_new_messages)
                      user_msg = Message.new(role: :user, content: fix_empty_final_user_text)
                      messages << user_msg
                      all_new_messages << user_msg
                      next :continue
                    end

                    yield StreamEvent::TurnEnd.new(
                      turn_number: turn,
                      message: assistant_msg,
                      stop_reason: response_stop_reason,
                      usage: response_usage
                    ) if block
                    events.emit(:turn_end, turn, all_new_messages)

                    stop_reason = response_stop_reason
                    completed_turns = turn
                    run_payload[:stop_reason] = stop_reason
                    :stop
                  ensure
                    turn_payload[:stop_reason] ||= turn_stop_reason
                    turn_payload[:usage] ||= turn_usage_obj&.to_h if turn_usage_obj
                  end
                end

              turn_ended_at = clock.now

              turn_traces <<
                TurnTrace.new(
                  turn_number: turn,
                  started_at: turn_started_at,
                  ended_at: turn_ended_at,
                  duration_ms: turn_payload.fetch(:duration_ms, nil),
                  llm: llm_trace,
                  tool_authorizations: tool_authorization_traces,
                  tool_executions: tool_execution_traces,
                  stop_reason: turn_stop_reason,
                  usage: turn_usage_obj&.to_h,
                )

              break if turn_outcome == :stop
            end
          ensure
            run_payload[:turns] ||= completed_turns
            run_payload[:usage] ||= aggregated_usage&.to_h if aggregated_usage
          end
        end

        run_ended_at = clock.now
        run_duration_ms = (clock.monotonic - run_started_mono) * 1000.0

        run_trace =
          RunTrace.new(
            run_id: run_id,
            started_at: run_started_at,
            ended_at: run_ended_at,
            duration_ms: run_duration_ms,
            turns: turn_traces,
            stop_reason: stop_reason,
            usage: aggregated_usage&.to_h,
          )

        yield StreamEvent::Done.new(stop_reason: stop_reason, usage: aggregated_usage) if block

        if pause_state
          ensure_pause_state_ids!(pause_state)

          pause_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
          pending_tool_confirmations =
            pause_reason == :awaiting_tool_confirmation ? pause_state.fetch(:pending_tool_confirmations) : []
          pending_tool_executions =
            pause_reason == :awaiting_tool_results ? pause_state.fetch(:pending_tool_executions) : []

          continuation =
            Continuation.new(
              run_id: run_id,
              continuation_id: normalize_optional_id(pause_state[:continuation_id]),
              parent_continuation_id: normalize_optional_id(pause_state[:parent_continuation_id]),
              started_at: run_started_at,
              duration_ms: run_duration_ms,
              turn: completed_turns,
              max_turns: max_turns,
              messages: messages.dup.freeze,
              model: model,
              options: options.dup.freeze,
              tools: prompt.tools,
              tools_enabled: tools_enabled,
              empty_final_fixup_attempted: empty_final_fixup_attempted,
              any_tool_calls_seen: any_tool_calls_seen,
              tool_calls_record: tool_calls_record.dup.freeze,
              aggregated_usage: aggregated_usage,
              per_turn_usage: per_turn_usage.dup.freeze,
              turn_traces: turn_traces.dup.freeze,
              pause_reason: pause_reason,
              pending_tool_calls: pause_state.fetch(:pending_tool_calls),
              pending_tool_executions: pending_tool_executions,
              buffered_tool_results: buffered_tool_results_for(pause_state),
              pending_decisions: pause_state.fetch(:pending_decisions),
              context_attributes: execution_context.attributes,
              max_tool_output_bytes: max_tool_output_bytes,
              max_tool_calls_per_turn: max_tool_calls_per_turn,
              fix_empty_final: fix_empty_final,
              fix_empty_final_user_text: fix_empty_final_user_text,
              fix_empty_final_disable_tools: fix_empty_final_disable_tools,
            )
        end

        build_result(
          run_id: run_id,
          started_at: run_started_at,
          ended_at: run_ended_at,
          duration_ms: run_duration_ms,
          trace: run_trace,
          all_new_messages: all_new_messages,
          turns: completed_turns,
          usage: aggregated_usage,
          tool_calls_record: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage,
          pending_tool_confirmations: pending_tool_confirmations,
          pending_tool_executions: pending_tool_executions,
          continuation: continuation
        )
      end

      # Resume a paused run after providing tool confirmations.
      #
      # @param continuation [Continuation, Hash, String] RunResult#continuation (or a ContinuationCodec payload)
      # @param tool_confirmations [Hash{String=>Symbol,Boolean}] tool_call_id => :allow/:deny (or true/false)
      # @return [RunResult]
      def resume(continuation:, tool_confirmations:, provider:, tools_registry:, tool_policy: nil, events: nil,
                 token_counter: nil, context_window: nil, reserved_output_tokens: 0,
                 context: nil, instrumenter: nil, tool_executor: ToolExecutor::Inline.new)
        continuation = coerce_continuation(continuation)

        pending_tool_calls = Array(continuation.pending_tool_calls)
        if pending_tool_calls.empty?
          raise ArgumentError, "continuation has no pending tool calls"
        end

        if continuation.respond_to?(:pause_reason) && continuation.pause_reason && continuation.pause_reason != :awaiting_tool_confirmation
          raise ArgumentError, "continuation pause_reason is #{continuation.pause_reason.inspect} (expected :awaiting_tool_confirmation)"
        end

        raise ArgumentError, "provider is required" unless provider
        raise ArgumentError, "tools_registry is required" unless tools_registry

        events ||= Events.new

        base_context = context || continuation.context_attributes
        execution_context = ExecutionContext.from(base_context, instrumenter: instrumenter).with(run_id: continuation.run_id)
        instrumenter = execution_context.instrumenter
        clock = execution_context.clock
        run_id = execution_context.run_id

        publish_resume_event(
          instrumenter,
          run_id: run_id,
          paused_turn_number: continuation.turn,
          pause_reason: continuation.pause_reason,
          continuation_id: continuation.continuation_id,
        )

        messages = continuation.messages.dup
        tool_calls_record = continuation.tool_calls_record.dup
        aggregated_usage = continuation.aggregated_usage
        per_turn_usage = continuation.per_turn_usage.dup
        turn_traces = continuation.turn_traces.dup

        prompt_tools = continuation.tools
        options = continuation.options.dup
        model = continuation.model

        turn = continuation.turn
        max_turns = continuation.max_turns
        tools_enabled = continuation.tools_enabled
        empty_final_fixup_attempted = continuation.empty_final_fixup_attempted
        any_tool_calls_seen = continuation.any_tool_calls_seen

        fix_empty_final = continuation.fix_empty_final
        fix_empty_final_user_text = continuation.fix_empty_final_user_text.to_s
        fix_empty_final_disable_tools = continuation.fix_empty_final_disable_tools
        max_tool_output_bytes = continuation.max_tool_output_bytes
        max_tool_calls_per_turn = continuation.max_tool_calls_per_turn

        run_started_at = continuation.started_at
        prior_duration_ms = continuation.duration_ms.to_f
        run_started_mono = clock.monotonic

        all_new_messages = []
        pending_tool_confirmations = []
        pending_tool_executions = []
        next_continuation = nil
        pause_state = nil

        stop_reason = :end_turn
        completed_turns = turn

        run_payload = { run_id: run_id, resumed: true }

        instrumenter.instrument("agent_core.run", run_payload) do
          begin
            resolved_decisions, confirmation_traces =
              resolve_pending_tool_confirmations(
                pending_tool_calls: pending_tool_calls,
                pending_decisions: continuation.pending_decisions,
                tool_confirmations: tool_confirmations,
              )

            publish_confirmation_authorizations!(
              instrumenter: instrumenter,
              run_id: run_id,
              paused_turn_number: turn,
              pending_tool_calls: pending_tool_calls,
              confirmation_traces: confirmation_traces,
              resumed: true,
              tools_registry: tools_registry,
            )

            tool_result_messages, exec_traces, exec_pause_state =
              execute_tool_calls_with_decisions(
                tool_calls: pending_tool_calls,
                decisions: resolved_decisions,
                tools_registry: tools_registry,
                tool_executor: tool_executor,
                events: events,
                tool_calls_record: tool_calls_record,
                max_tool_output_bytes: max_tool_output_bytes,
                turn_number: turn,
                execution_context: execution_context,
                stream_block: nil,
                args_summaries: {},
              )

            tool_result_messages.each do |msg|
              messages << msg
              all_new_messages << msg
            end

            apply_resume_tool_traces!(
              turn_traces: turn_traces,
              paused_turn_number: turn,
              confirmation_traces: confirmation_traces,
              execution_traces: exec_traces,
            )

            if exec_pause_state
              pause_state = exec_pause_state
              stop_reason = pause_state.fetch(:reason, :awaiting_tool_results)
              run_payload[:stop_reason] = stop_reason
              completed_turns = turn
              publish_pause_event(
                instrumenter,
                run_id: run_id,
                turn_number: turn,
                pause_state: pause_state,
                parent_continuation_id: continuation&.continuation_id,
              )
              next
            end

          if turn >= max_turns
            completed_turns = turn
            stop_reason = :max_turns
            run_payload[:stop_reason] = stop_reason
            next
          end

          loop do
            turn += 1

            if turn > max_turns
              completed_turns = turn - 1
              stop_reason = :max_turns
              run_payload[:stop_reason] = stop_reason
              events.emit(:error, MaxTurnsExceededError.new(turns: max_turns), false)
              break
            end

            turn_started_at = clock.now
            turn_payload = { run_id: run_id, turn_number: turn }

            tool_authorization_traces = []
            tool_execution_traces = []
            llm_trace = nil
            turn_stop_reason = :end_turn
            turn_usage_obj = nil

            turn_outcome =
              instrumenter.instrument("agent_core.turn", turn_payload) do
                begin
                  events.emit(:turn_start, turn)

                tools = tools_enabled && prompt_tools && !prompt_tools.empty? ? prompt_tools : nil
                request_messages = messages.dup.freeze

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

                llm_payload = {
                  run_id: run_id,
                  turn_number: turn,
                  model: model,
                  stream: false,
                  messages_count: request_messages.size,
                  tools_count: tools ? tools.size : 0,
                  options_summary: summarize_llm_options(options),
                }

                response =
                  instrumenter.instrument("agent_core.llm.call", llm_payload) do
                    resp =
                      provider.chat(
                        messages: request_messages,
                        model: model,
                        tools: tools,
                        stream: false,
                        **options
                      )
                    llm_payload[:stop_reason] = resp.stop_reason
                    llm_payload[:usage] = resp.usage&.to_h
                    resp
                  end

                llm_trace =
                  LlmCallTrace.new(
                    model: model.to_s,
                    messages_count: request_messages.size,
                    tools_count: tools ? tools.size : 0,
                    options_summary: llm_payload.fetch(:options_summary),
                    stop_reason: llm_payload.fetch(:stop_reason, nil),
                    usage: llm_payload.fetch(:usage, nil),
                    duration_ms: llm_payload.fetch(:duration_ms, nil),
                  )

                assistant_msg = response.message
                turn_stop_reason = response.stop_reason
                turn_usage_obj = response.usage

                if response.usage
                  per_turn_usage << response.usage
                  aggregated_usage = aggregated_usage ? aggregated_usage + response.usage : response.usage
                end

                messages << assistant_msg
                all_new_messages << assistant_msg
                events.emit(:llm_response, response)

                effective_max_tool_calls_per_turn =
                  if max_tool_calls_per_turn
                    limit = Integer(max_tool_calls_per_turn)
                    raise ArgumentError, "max_tool_calls_per_turn must be positive" if limit <= 0
                    limit
                  elsif options.fetch(:parallel_tool_calls, nil) == false
                    1
                  end

                tool_calls = assistant_msg.tool_calls || []

                if tools_registry && tools && effective_max_tool_calls_per_turn && tool_calls.size > effective_max_tool_calls_per_turn
                  ignored = tool_calls.drop(effective_max_tool_calls_per_turn)

                  ignored.each do |tc|
                    tool_calls_record << {
                      name: tc.name,
                      arguments: tc.arguments,
                      error: "ignored: max_tool_calls_per_turn=#{effective_max_tool_calls_per_turn}",
                    }
                  end

                  tool_calls = tool_calls.first(effective_max_tool_calls_per_turn)

                  assistant_msg =
                    Message.new(
                      role: assistant_msg.role,
                      content: assistant_msg.content,
                      tool_calls: tool_calls.empty? ? nil : tool_calls,
                      tool_call_id: assistant_msg.tool_call_id,
                      name: assistant_msg.name,
                      metadata: assistant_msg.metadata,
                    )
                  messages[-1] = assistant_msg
                  all_new_messages[-1] = assistant_msg
                elsif tools.nil? && assistant_msg.has_tool_calls?
                  assistant_msg =
                    Message.new(
                      role: assistant_msg.role,
                      content: assistant_msg.content,
                      tool_calls: nil,
                      tool_call_id: assistant_msg.tool_call_id,
                      name: assistant_msg.name,
                      metadata: assistant_msg.metadata,
                    )
                  tool_calls = []
                  messages[-1] = assistant_msg
                  all_new_messages[-1] = assistant_msg
                end

                any_tool_calls_seen ||= tool_calls.any? if tools_registry && tools

                if tool_calls.any? && tools_registry && tools
                    tool_processing =
                      process_tool_calls_for_turn(
                        tool_calls: tool_calls,
                        tools_registry: tools_registry,
                        tool_policy: tool_policy,
                        tool_executor: tool_executor,
                        events: events,
                        tool_calls_record: tool_calls_record,
                        max_tool_output_bytes: max_tool_output_bytes,
                        turn_number: turn,
                        execution_context: execution_context,
                        stream_block: nil
                      )

                  tool_authorization_traces.concat(tool_processing.fetch(:authorization_traces))
                  tool_execution_traces.concat(tool_processing.fetch(:execution_traces))

                  Array(tool_processing[:result_messages]).each do |result_msg|
                    messages << result_msg
                    all_new_messages << result_msg
                  end

                  if tool_processing[:pause_state]
                    pause_state = tool_processing.fetch(:pause_state)
                    stop_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
                    turn_stop_reason = stop_reason
                    completed_turns = turn
                    run_payload[:stop_reason] = stop_reason
                    publish_pause_event(
                      instrumenter,
                      run_id: run_id,
                      turn_number: turn,
                      pause_state: pause_state,
                      parent_continuation_id: continuation&.continuation_id,
                    )
                    events.emit(:turn_end, turn, all_new_messages)
                    next :stop
                  end

                  events.emit(:turn_end, turn, all_new_messages)
                  next :continue
                end

                if fix_empty_final &&
                    !empty_final_fixup_attempted &&
                    tools_registry &&
                    any_tool_calls_seen &&
                    assistant_msg.assistant? &&
                    assistant_msg.text.to_s.strip.empty?
                  empty_final_fixup_attempted = true
                  tools_enabled = false if fix_empty_final_disable_tools
                  events.emit(:turn_end, turn, all_new_messages)
                  user_msg = Message.new(role: :user, content: fix_empty_final_user_text)
                  messages << user_msg
                  all_new_messages << user_msg
                  next :continue
                end

                  events.emit(:turn_end, turn, all_new_messages)
                  stop_reason = turn_stop_reason
                  completed_turns = turn
                  run_payload[:stop_reason] = stop_reason
                  :stop
                ensure
                  turn_payload[:stop_reason] ||= turn_stop_reason
                  turn_payload[:usage] ||= turn_usage_obj&.to_h if turn_usage_obj
                end
              end

            turn_ended_at = clock.now

            turn_traces <<
              TurnTrace.new(
                turn_number: turn,
                started_at: turn_started_at,
                ended_at: turn_ended_at,
                duration_ms: turn_payload.fetch(:duration_ms, nil),
                llm: llm_trace,
                tool_authorizations: tool_authorization_traces,
                tool_executions: tool_execution_traces,
                stop_reason: turn_stop_reason,
                usage: turn_usage_obj&.to_h,
              )

            break if turn_outcome == :stop
          end
          ensure
            run_payload[:turns] ||= completed_turns
            run_payload[:usage] ||= aggregated_usage&.to_h if aggregated_usage
          end
        end

        run_ended_at = clock.now
        segment_duration_ms = (clock.monotonic - run_started_mono) * 1000.0
        run_duration_ms = prior_duration_ms + segment_duration_ms

        run_trace =
          RunTrace.new(
            run_id: run_id,
            started_at: run_started_at,
            ended_at: run_ended_at,
            duration_ms: run_duration_ms,
            turns: turn_traces,
            stop_reason: stop_reason,
            usage: aggregated_usage&.to_h,
          )

        if pause_state
          ensure_pause_state_ids!(pause_state, parent_continuation_id: continuation&.continuation_id)

          pause_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
          pending_tool_confirmations =
            pause_reason == :awaiting_tool_confirmation ? pause_state.fetch(:pending_tool_confirmations) : []
          pending_tool_executions =
            pause_reason == :awaiting_tool_results ? pause_state.fetch(:pending_tool_executions) : []

          next_continuation =
            Continuation.new(
              run_id: run_id,
              continuation_id: normalize_optional_id(pause_state[:continuation_id]),
              parent_continuation_id: normalize_optional_id(pause_state[:parent_continuation_id]),
              started_at: run_started_at,
              duration_ms: run_duration_ms,
              turn: completed_turns,
              max_turns: max_turns,
              messages: messages.dup.freeze,
              model: model,
              options: options.dup.freeze,
              tools: prompt_tools,
              tools_enabled: tools_enabled,
              empty_final_fixup_attempted: empty_final_fixup_attempted,
              any_tool_calls_seen: any_tool_calls_seen,
              tool_calls_record: tool_calls_record.dup.freeze,
              aggregated_usage: aggregated_usage,
              per_turn_usage: per_turn_usage.dup.freeze,
              turn_traces: turn_traces.dup.freeze,
              pause_reason: pause_reason,
              pending_tool_calls: pause_state.fetch(:pending_tool_calls),
              pending_tool_executions: pending_tool_executions,
              buffered_tool_results: buffered_tool_results_for(pause_state),
              pending_decisions: pause_state.fetch(:pending_decisions),
              context_attributes: execution_context.attributes,
              max_tool_output_bytes: max_tool_output_bytes,
              max_tool_calls_per_turn: max_tool_calls_per_turn,
              fix_empty_final: fix_empty_final,
              fix_empty_final_user_text: fix_empty_final_user_text,
              fix_empty_final_disable_tools: fix_empty_final_disable_tools,
            )
        end

        build_result(
          run_id: run_id,
          started_at: run_started_at,
          ended_at: run_ended_at,
          duration_ms: run_duration_ms,
          trace: run_trace,
          all_new_messages: all_new_messages,
          turns: completed_turns,
          usage: aggregated_usage,
          tool_calls_record: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage,
          pending_tool_confirmations: pending_tool_confirmations,
          pending_tool_executions: pending_tool_executions,
          continuation: next_continuation,
        )
      end

      # Resume a paused run with streaming events.
      #
      # @param continuation [Continuation, Hash, String] RunResult#continuation (or a ContinuationCodec payload)
      def resume_stream(continuation:, tool_confirmations:, provider:, tools_registry:, tool_policy: nil, events: nil,
                        token_counter: nil, context_window: nil, reserved_output_tokens: 0,
                        context: nil, instrumenter: nil, tool_executor: ToolExecutor::Inline.new, &block)
        continuation = coerce_continuation(continuation)

        pending_tool_calls = Array(continuation.pending_tool_calls)
        if pending_tool_calls.empty?
          raise ArgumentError, "continuation has no pending tool calls"
        end

        if continuation.respond_to?(:pause_reason) && continuation.pause_reason && continuation.pause_reason != :awaiting_tool_confirmation
          raise ArgumentError, "continuation pause_reason is #{continuation.pause_reason.inspect} (expected :awaiting_tool_confirmation)"
        end

        raise ArgumentError, "provider is required" unless provider
        raise ArgumentError, "tools_registry is required" unless tools_registry

        events ||= Events.new

        base_context = context || continuation.context_attributes
        execution_context = ExecutionContext.from(base_context, instrumenter: instrumenter).with(run_id: continuation.run_id)
        instrumenter = execution_context.instrumenter
        clock = execution_context.clock
        run_id = execution_context.run_id

        publish_resume_event(
          instrumenter,
          run_id: run_id,
          paused_turn_number: continuation.turn,
          pause_reason: continuation.pause_reason,
          continuation_id: continuation.continuation_id,
        )

        messages = continuation.messages.dup
        tool_calls_record = continuation.tool_calls_record.dup
        aggregated_usage = continuation.aggregated_usage
        per_turn_usage = continuation.per_turn_usage.dup
        turn_traces = continuation.turn_traces.dup

        prompt_tools = continuation.tools
        options = continuation.options.dup
        model = continuation.model

        turn = continuation.turn
        max_turns = continuation.max_turns
        tools_enabled = continuation.tools_enabled
        empty_final_fixup_attempted = continuation.empty_final_fixup_attempted
        any_tool_calls_seen = continuation.any_tool_calls_seen

        fix_empty_final = continuation.fix_empty_final
        fix_empty_final_user_text = continuation.fix_empty_final_user_text.to_s
        fix_empty_final_disable_tools = continuation.fix_empty_final_disable_tools
        max_tool_output_bytes = continuation.max_tool_output_bytes
        max_tool_calls_per_turn = continuation.max_tool_calls_per_turn

        run_started_at = continuation.started_at
        prior_duration_ms = continuation.duration_ms.to_f
        run_started_mono = clock.monotonic

        all_new_messages = []
        pending_tool_confirmations = []
        pending_tool_executions = []
        next_continuation = nil
        pause_state = nil

        stop_reason = :end_turn
        completed_turns = turn

        run_payload = { run_id: run_id, resumed: true, stream: true }

        instrumenter.instrument("agent_core.run", run_payload) do
          begin
            resolved_decisions, confirmation_traces =
              resolve_pending_tool_confirmations(
                pending_tool_calls: pending_tool_calls,
                pending_decisions: continuation.pending_decisions,
                tool_confirmations: tool_confirmations,
              )

            publish_confirmation_authorizations!(
              instrumenter: instrumenter,
              run_id: run_id,
              paused_turn_number: turn,
              pending_tool_calls: pending_tool_calls,
              confirmation_traces: confirmation_traces,
              resumed: true,
              tools_registry: tools_registry,
            )

              tool_result_messages, exec_traces, exec_pause_state =
                execute_tool_calls_with_decisions(
                  tool_calls: pending_tool_calls,
                  decisions: resolved_decisions,
                  tools_registry: tools_registry,
                  tool_executor: tool_executor,
                  events: events,
                  tool_calls_record: tool_calls_record,
                  max_tool_output_bytes: max_tool_output_bytes,
                  turn_number: turn,
                  execution_context: execution_context,
                  stream_block: block,
                  args_summaries: {},
                )

              tool_result_messages.each do |msg|
                messages << msg
                all_new_messages << msg
              end

              apply_resume_tool_traces!(
                turn_traces: turn_traces,
                paused_turn_number: turn,
                confirmation_traces: confirmation_traces,
                execution_traces: exec_traces,
              )

              if exec_pause_state
                pause_state = exec_pause_state
                stop_reason = pause_state.fetch(:reason, :awaiting_tool_results)
                run_payload[:stop_reason] = stop_reason
                completed_turns = turn
                publish_pause_event(
                  instrumenter,
                  run_id: run_id,
                  turn_number: turn,
                  pause_state: pause_state,
                  parent_continuation_id: continuation&.continuation_id,
                )

                case stop_reason
                when :awaiting_tool_confirmation
                  yield StreamEvent::AuthorizationRequired.new(
                    run_id: run_id,
                    pending_tool_confirmations: pause_state.fetch(:pending_tool_confirmations),
                  ) if block
                when :awaiting_tool_results
                  yield StreamEvent::ToolExecutionRequired.new(
                    run_id: run_id,
                    pending_tool_executions: pause_state.fetch(:pending_tool_executions),
                  ) if block
                end

                next
              end

            if turn >= max_turns
              completed_turns = turn
              stop_reason = :max_turns
              run_payload[:stop_reason] = stop_reason
              next
            end

          loop do
            turn += 1

            if turn > max_turns
              completed_turns = turn - 1
              stop_reason = :max_turns
              run_payload[:stop_reason] = stop_reason
              yield StreamEvent::ErrorEvent.new(error: "Max turns exceeded", recoverable: false) if block
              break
            end

            yield StreamEvent::TurnStart.new(turn_number: turn) if block
            events.emit(:turn_start, turn)

            turn_started_at = clock.now
            turn_payload = { run_id: run_id, turn_number: turn }

            tool_authorization_traces = []
            tool_execution_traces = []
            llm_trace = nil
            turn_stop_reason = :end_turn
            turn_usage_obj = nil

            turn_outcome =
              instrumenter.instrument("agent_core.turn", turn_payload) do
                begin
                  tools = tools_enabled && prompt_tools && !prompt_tools.empty? ? prompt_tools : nil
                  request_messages = messages.dup.freeze

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

                assistant_msg = nil
                response_stop_reason = :end_turn
                response_usage = nil

                llm_payload = {
                  run_id: run_id,
                  turn_number: turn,
                  model: model,
                  stream: true,
                  messages_count: request_messages.size,
                  tools_count: tools ? tools.size : 0,
                  options_summary: summarize_llm_options(options),
                }

                instrumenter.instrument("agent_core.llm.call", llm_payload) do
                  stream_enum =
                    provider.chat(
                      messages: request_messages,
                      model: model,
                      tools: tools,
                      stream: true,
                      **options
                    )

                  stream_enum.each do |event|
                    events.emit(:stream_delta, event)

                    case event
                    when StreamEvent::Done
                      response_stop_reason = event.stop_reason
                      response_usage = event.usage
                      next
                    when StreamEvent::MessageComplete
                      assistant_msg = event.message
                    end

                    yield event if block
                  end

                  llm_payload[:stop_reason] = response_stop_reason
                  llm_payload[:usage] = response_usage&.to_h

                  nil
                end

                llm_trace =
                  LlmCallTrace.new(
                    model: model.to_s,
                    messages_count: request_messages.size,
                    tools_count: tools ? tools.size : 0,
                    options_summary: llm_payload.fetch(:options_summary),
                    stop_reason: llm_payload.fetch(:stop_reason, nil),
                    usage: llm_payload.fetch(:usage, nil),
                    duration_ms: llm_payload.fetch(:duration_ms, nil),
                  )

                turn_usage_obj = response_usage
                turn_stop_reason = response_stop_reason

                if response_usage
                  per_turn_usage << response_usage
                  aggregated_usage = aggregated_usage ? aggregated_usage + response_usage : response_usage
                end

                unless assistant_msg
                  yield StreamEvent::ErrorEvent.new(
                    error: "Provider stream ended without producing a MessageComplete event",
                    recoverable: false
                  ) if block
                  stop_reason = :error
                  completed_turns = turn
                  run_payload[:stop_reason] = stop_reason
                  events.emit(:turn_end, turn, all_new_messages)
                  next :stop
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

                effective_max_tool_calls_per_turn =
                  if max_tool_calls_per_turn
                    limit = Integer(max_tool_calls_per_turn)
                    raise ArgumentError, "max_tool_calls_per_turn must be positive" if limit <= 0
                    limit
                  elsif options.fetch(:parallel_tool_calls, nil) == false
                    1
                  end

                tool_calls = assistant_msg.tool_calls || []

                if tools_registry && tools && effective_max_tool_calls_per_turn && tool_calls.size > effective_max_tool_calls_per_turn
                  ignored = tool_calls.drop(effective_max_tool_calls_per_turn)

                  ignored.each do |tc|
                    tool_calls_record << {
                      name: tc.name,
                      arguments: tc.arguments,
                      error: "ignored: max_tool_calls_per_turn=#{effective_max_tool_calls_per_turn}",
                    }
                  end

                  tool_calls = tool_calls.first(effective_max_tool_calls_per_turn)

                  assistant_msg =
                    Message.new(
                      role: assistant_msg.role,
                      content: assistant_msg.content,
                      tool_calls: tool_calls.empty? ? nil : tool_calls,
                      tool_call_id: assistant_msg.tool_call_id,
                      name: assistant_msg.name,
                      metadata: assistant_msg.metadata,
                    )
                  messages[-1] = assistant_msg
                  all_new_messages[-1] = assistant_msg
                elsif tools.nil? && assistant_msg.has_tool_calls?
                  assistant_msg =
                    Message.new(
                      role: assistant_msg.role,
                      content: assistant_msg.content,
                      tool_calls: nil,
                      tool_call_id: assistant_msg.tool_call_id,
                      name: assistant_msg.name,
                      metadata: assistant_msg.metadata,
                    )
                  tool_calls = []
                  messages[-1] = assistant_msg
                  all_new_messages[-1] = assistant_msg
                end

                any_tool_calls_seen ||= tool_calls.any? if tools_registry && tools

                if tool_calls.any? && tools_registry && tools
                    tool_processing =
                      process_tool_calls_for_turn(
                        tool_calls: tool_calls,
                        tools_registry: tools_registry,
                        tool_policy: tool_policy,
                        tool_executor: tool_executor,
                        events: events,
                        tool_calls_record: tool_calls_record,
                        max_tool_output_bytes: max_tool_output_bytes,
                        turn_number: turn,
                        execution_context: execution_context,
                        stream_block: block
                      )

                  tool_authorization_traces.concat(tool_processing.fetch(:authorization_traces))
                  tool_execution_traces.concat(tool_processing.fetch(:execution_traces))

                  Array(tool_processing[:result_messages]).each do |result_msg|
                    messages << result_msg
                    all_new_messages << result_msg
                  end

                  yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg, stop_reason: response_stop_reason, usage: response_usage) if block
                  events.emit(:turn_end, turn, all_new_messages)

                  if tool_processing[:pause_state]
                    pause_state = tool_processing.fetch(:pause_state)
                    stop_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
                    turn_stop_reason = stop_reason
                    completed_turns = turn
                    run_payload[:stop_reason] = stop_reason
                    publish_pause_event(
                      instrumenter,
                      run_id: run_id,
                      turn_number: turn,
                      pause_state: pause_state,
                      parent_continuation_id: continuation&.continuation_id,
                    )

                    case stop_reason
                    when :awaiting_tool_confirmation
                      yield StreamEvent::AuthorizationRequired.new(
                        run_id: run_id,
                        pending_tool_confirmations: pause_state.fetch(:pending_tool_confirmations),
                      ) if block
                    when :awaiting_tool_results
                      yield StreamEvent::ToolExecutionRequired.new(
                        run_id: run_id,
                        pending_tool_executions: pause_state.fetch(:pending_tool_executions),
                      ) if block
                    end
                    next :stop
                  end

                  next :continue
                end

                if fix_empty_final &&
                    !empty_final_fixup_attempted &&
                    tools_registry &&
                    any_tool_calls_seen &&
                    assistant_msg.assistant? &&
                    assistant_msg.text.to_s.strip.empty?
                  empty_final_fixup_attempted = true
                  tools_enabled = false if fix_empty_final_disable_tools
                  yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg, stop_reason: response_stop_reason, usage: response_usage) if block
                  events.emit(:turn_end, turn, all_new_messages)
                  user_msg = Message.new(role: :user, content: fix_empty_final_user_text)
                  messages << user_msg
                  all_new_messages << user_msg
                  next :continue
                end

                yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg, stop_reason: response_stop_reason, usage: response_usage) if block
                events.emit(:turn_end, turn, all_new_messages)

                  stop_reason = response_stop_reason
                  completed_turns = turn
                  run_payload[:stop_reason] = stop_reason
                  :stop
                ensure
                  turn_payload[:stop_reason] ||= turn_stop_reason
                  turn_payload[:usage] ||= turn_usage_obj&.to_h if turn_usage_obj
                end
              end

            turn_ended_at = clock.now

            turn_traces <<
              TurnTrace.new(
                turn_number: turn,
                started_at: turn_started_at,
                ended_at: turn_ended_at,
                duration_ms: turn_payload.fetch(:duration_ms, nil),
                llm: llm_trace,
                tool_authorizations: tool_authorization_traces,
                tool_executions: tool_execution_traces,
                stop_reason: turn_stop_reason,
                usage: turn_usage_obj&.to_h,
              )

            break if turn_outcome == :stop
          end
          ensure
            run_payload[:turns] ||= completed_turns
            run_payload[:usage] ||= aggregated_usage&.to_h if aggregated_usage
          end
        end

        run_ended_at = clock.now
        segment_duration_ms = (clock.monotonic - run_started_mono) * 1000.0
        run_duration_ms = prior_duration_ms + segment_duration_ms

        run_trace =
          RunTrace.new(
            run_id: run_id,
            started_at: run_started_at,
            ended_at: run_ended_at,
            duration_ms: run_duration_ms,
            turns: turn_traces,
            stop_reason: stop_reason,
            usage: aggregated_usage&.to_h,
          )

        yield StreamEvent::Done.new(stop_reason: stop_reason, usage: aggregated_usage) if block

        if pause_state
          ensure_pause_state_ids!(pause_state, parent_continuation_id: continuation&.continuation_id)

          pause_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
          pending_tool_confirmations =
            pause_reason == :awaiting_tool_confirmation ? pause_state.fetch(:pending_tool_confirmations) : []
          pending_tool_executions =
            pause_reason == :awaiting_tool_results ? pause_state.fetch(:pending_tool_executions) : []

          next_continuation =
            Continuation.new(
              run_id: run_id,
              continuation_id: normalize_optional_id(pause_state[:continuation_id]),
              parent_continuation_id: normalize_optional_id(pause_state[:parent_continuation_id]),
              started_at: run_started_at,
              duration_ms: run_duration_ms,
              turn: completed_turns,
              max_turns: max_turns,
              messages: messages.dup.freeze,
              model: model,
              options: options.dup.freeze,
              tools: prompt_tools,
              tools_enabled: tools_enabled,
              empty_final_fixup_attempted: empty_final_fixup_attempted,
              any_tool_calls_seen: any_tool_calls_seen,
              tool_calls_record: tool_calls_record.dup.freeze,
              aggregated_usage: aggregated_usage,
              per_turn_usage: per_turn_usage.dup.freeze,
              turn_traces: turn_traces.dup.freeze,
              pause_reason: pause_reason,
              pending_tool_calls: pause_state.fetch(:pending_tool_calls),
              pending_tool_executions: pending_tool_executions,
              buffered_tool_results: buffered_tool_results_for(pause_state),
              pending_decisions: pause_state.fetch(:pending_decisions),
              context_attributes: execution_context.attributes,
              max_tool_output_bytes: max_tool_output_bytes,
              max_tool_calls_per_turn: max_tool_calls_per_turn,
              fix_empty_final: fix_empty_final,
              fix_empty_final_user_text: fix_empty_final_user_text,
              fix_empty_final_disable_tools: fix_empty_final_disable_tools,
            )
        end

        build_result(
          run_id: run_id,
          started_at: run_started_at,
          ended_at: run_ended_at,
          duration_ms: run_duration_ms,
          trace: run_trace,
          all_new_messages: all_new_messages,
          turns: completed_turns,
          usage: aggregated_usage,
          tool_calls_record: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage,
          pending_tool_confirmations: pending_tool_confirmations,
          pending_tool_executions: pending_tool_executions,
          continuation: next_continuation,
        )
      end

      # Resume a paused run after receiving external tool execution results.
      #
      # This is used when the run stopped with `stop_reason=:awaiting_tool_results`
      # (typically via a `ToolExecutor::DeferAll` strategy), and the app executes
      # tools out-of-band (ActiveJob, MQ, etc.).
      #
      # @param continuation [Continuation, Hash, String] RunResult#continuation (or a ContinuationCodec payload)
      # @param tool_results [Hash{String=>Resources::Tools::ToolResult}] tool_call_id => ToolResult
      # @return [RunResult]
      def resume_with_tool_results(continuation:, tool_results:, provider:, tools_registry:, tool_policy: nil, events: nil,
                                   token_counter: nil, context_window: nil, reserved_output_tokens: 0,
                                   context: nil, instrumenter: nil, tool_executor: ToolExecutor::Inline.new, allow_partial: false)
        continuation = coerce_continuation(continuation)

        if continuation.pause_reason != :awaiting_tool_results
          raise ArgumentError, "continuation pause_reason is #{continuation.pause_reason.inspect} (expected :awaiting_tool_results)"
        end

        pending_tool_executions = Array(continuation.pending_tool_executions)
        if pending_tool_executions.empty?
          raise ArgumentError, "continuation has no pending tool executions"
        end

        pending_tool_calls = Array(continuation.pending_tool_calls)
        if pending_tool_calls.empty?
          raise ArgumentError, "continuation has no pending tool calls"
        end

        buffered_tool_results =
          if continuation.respond_to?(:buffered_tool_results) && continuation.buffered_tool_results.is_a?(Hash)
            continuation.buffered_tool_results
          else
            {}
          end

        buffered_tool_results =
          buffered_tool_results.each_with_object({}) do |(tool_call_id, result), out|
            id = tool_call_id.to_s
            next if id.strip.empty?
            next unless result.is_a?(Resources::Tools::ToolResult)

            out[id] = result
          end

        allow_partial = allow_partial == true

        raise ArgumentError, "tool_results must be a Hash" unless tool_results.is_a?(Hash)

        raise ArgumentError, "provider is required" unless provider
        raise ArgumentError, "tools_registry is required" unless tools_registry

        events ||= Events.new

        base_context = context || continuation.context_attributes
        execution_context = ExecutionContext.from(base_context, instrumenter: instrumenter).with(run_id: continuation.run_id)
        instrumenter = execution_context.instrumenter
        clock = execution_context.clock
        run_id = execution_context.run_id

        publish_resume_event(
          instrumenter,
          run_id: run_id,
          paused_turn_number: continuation.turn,
          pause_reason: continuation.pause_reason,
          continuation_id: continuation.continuation_id,
        )

        messages = continuation.messages.dup
        tool_calls_record = continuation.tool_calls_record.dup
        aggregated_usage = continuation.aggregated_usage
        per_turn_usage = continuation.per_turn_usage.dup
        turn_traces = continuation.turn_traces.dup

        prompt_tools = continuation.tools
        options = continuation.options.dup
        model = continuation.model

        turn = continuation.turn
        max_turns = continuation.max_turns
        tools_enabled = continuation.tools_enabled
        empty_final_fixup_attempted = continuation.empty_final_fixup_attempted
        any_tool_calls_seen = continuation.any_tool_calls_seen

        fix_empty_final = continuation.fix_empty_final
        fix_empty_final_user_text = continuation.fix_empty_final_user_text.to_s
        fix_empty_final_disable_tools = continuation.fix_empty_final_disable_tools
        max_tool_output_bytes = continuation.max_tool_output_bytes
        max_tool_calls_per_turn = continuation.max_tool_calls_per_turn

        run_started_at = continuation.started_at
        prior_duration_ms = continuation.duration_ms.to_f
        run_started_mono = clock.monotonic

        all_new_messages = []
        pending_tool_confirmations = []
        next_continuation = nil
        pause_state = nil

        stop_reason = :end_turn
        completed_turns = turn

        run_payload = { run_id: run_id, resumed: true, stage: "tool_results" }

        instrumenter.instrument("agent_core.run", run_payload) do
          begin
            external_exec_traces = []

            normalized_tool_results = {}

            tool_results.each do |tool_call_id, result|
              id = tool_call_id.to_s
              raise ArgumentError, "tool_results contains blank tool_call_id" if id.strip.empty?
              raise ArgumentError, "tool_results contains duplicate tool_call_id=#{id}" if normalized_tool_results.key?(id)

              normalized_tool_results[id] = result
            end

            pending_by_id = pending_tool_executions.each_with_object({}) do |pending, out|
              out[pending.tool_call_id.to_s] = pending
            end

            allowed_ids = pending_by_id.keys.to_h { |id| [id, true] }
            buffered_tool_results.each_key { |id| allowed_ids[id.to_s] = true }

            normalized_tool_results.each_key do |id|
              next if allowed_ids.key?(id)

              raise ArgumentError, "Unexpected tool result for tool_call_id=#{id}"
            end

            unless allow_partial
              missing =
                pending_tool_executions
                  .map { |p| p.tool_call_id.to_s }
                  .reject { |id| buffered_tool_results.key?(id) || normalized_tool_results.key?(id) }

              raise ArgumentError, "Missing tool result for tool_call_id=#{missing.first}" if missing.any?
            end

            pending_tool_executions.each do |pending|
              tool_call_id = pending.tool_call_id.to_s

              result = normalized_tool_results[tool_call_id]
              next if result.nil?

              unless result.is_a?(Resources::Tools::ToolResult)
                raise ArgumentError, "tool_results[#{tool_call_id.inspect}] must be a ToolResult (got #{result.class})"
              end

              result =
                ToolExecutionUtils.limit_tool_result(
                  result,
                  max_bytes: max_tool_output_bytes,
                  tool_name: pending.executed_name
                )

              existing = buffered_tool_results[tool_call_id]
              if existing
                next if existing.to_h == result.to_h

                raise ArgumentError, "Conflicting tool result for tool_call_id=#{tool_call_id}"
              end

              buffered_tool_results[tool_call_id] = result

              instrumenter.publish(
                "agent_core.tool.execute",
                {
                  run_id: run_id,
                  tool_call_id: tool_call_id,
                  name: pending.name.to_s,
                  executed_name: pending.executed_name.to_s,
                  source: pending.source.to_s,
                  stage: "external",
                  arguments_summary: pending.arguments_summary,
                  result_error: result.error?,
                  result_summary: ToolExecutionUtils.summarize_tool_result(result),
                  duration_ms: result.metadata.is_a?(Hash) ? result.metadata.fetch(:duration_ms, 0.0).to_f : 0.0,
                  turn_number: turn,
                }.compact
              )

              external_exec_traces <<
                ToolExecutionTrace.new(
                  tool_call_id: tool_call_id,
                  name: pending.name.to_s,
                  executed_name: pending.executed_name.to_s,
                  source: pending.source.to_s,
                  arguments_summary: pending.arguments_summary,
                  result_summary: ToolExecutionUtils.summarize_tool_result(result),
                  error: result.error? == true,
                  duration_ms: result.metadata.is_a?(Hash) ? result.metadata.fetch(:duration_ms, 0.0).to_f : 0.0,
                )

              tool_calls_record.each do |r|
                next unless r.is_a?(Hash) && r[:tool_call_id].to_s == tool_call_id

                r[:pending] = false
                r[:deferred] = false
                r[:external] = true
                r[:error] = result.error? ? result.text : nil
                break
              end

              events.emit(:tool_result, pending.name.to_s, result, tool_call_id)
            end

            normalized_tool_results.each do |tool_call_id, result|
              next if pending_by_id.key?(tool_call_id)

              existing = buffered_tool_results[tool_call_id]
              raise ArgumentError, "Unexpected tool result for tool_call_id=#{tool_call_id}" unless existing

              unless result.is_a?(Resources::Tools::ToolResult)
                raise ArgumentError, "tool_results[#{tool_call_id.inspect}] must be a ToolResult (got #{result.class})"
              end

              tool_name =
                tool_calls_record.find { |r| r.is_a?(Hash) && r[:tool_call_id].to_s == tool_call_id }&.fetch(:executed_name, nil).to_s
              tool_name = tool_call_id if tool_name.strip.empty?

              result = ToolExecutionUtils.limit_tool_result(result, max_bytes: max_tool_output_bytes, tool_name: tool_name)
              next if existing.to_h == result.to_h

              raise ArgumentError, "Conflicting tool result for tool_call_id=#{tool_call_id}"
            end

            apply_resume_tool_traces!(
              turn_traces: turn_traces,
              paused_turn_number: turn,
              confirmation_traces: [],
              execution_traces: external_exec_traces,
            )

            remaining =
              pending_tool_executions.reject do |pending|
                buffered_tool_results.key?(pending.tool_call_id.to_s)
              end

            if remaining.any?
              pause_state = {
                reason: :awaiting_tool_results,
                pending_tool_executions: remaining,
                pending_tool_calls: pending_tool_calls,
                pending_decisions: continuation.pending_decisions,
                buffered_tool_results: buffered_tool_results,
              }
              stop_reason = :awaiting_tool_results
              run_payload[:stop_reason] = stop_reason
              completed_turns = turn
              publish_pause_event(
                instrumenter,
                run_id: run_id,
                turn_number: turn,
                pause_state: pause_state,
                parent_continuation_id: continuation&.continuation_id,
              )
              next
            end

            pending_tool_calls.each do |tc|
              tool_call_id = tc.id.to_s
              result = buffered_tool_results.fetch(tool_call_id) do
                raise ArgumentError, "Missing buffered tool result for tool_call_id=#{tool_call_id}"
              end

              tool_result_message =
                tool_result_to_message(
                  result,
                  tool_call_id: tool_call_id,
                  name: tc.name.to_s,
                  max_tool_output_bytes: max_tool_output_bytes,
                )

              messages << tool_result_message
              all_new_messages << tool_result_message
            end

            if turn >= max_turns
              completed_turns = turn
              stop_reason = :max_turns
              run_payload[:stop_reason] = stop_reason
              next
            end

            loop do
              turn += 1

              if turn > max_turns
                completed_turns = turn - 1
                stop_reason = :max_turns
                run_payload[:stop_reason] = stop_reason
                events.emit(:error, MaxTurnsExceededError.new(turns: max_turns), false)
                break
              end

              turn_started_at = clock.now
              turn_payload = { run_id: run_id, turn_number: turn }

              tool_authorization_traces = []
              tool_execution_traces = []
              llm_trace = nil
              turn_stop_reason = :end_turn
              turn_usage_obj = nil

              turn_outcome =
                instrumenter.instrument("agent_core.turn", turn_payload) do
                  begin
                    events.emit(:turn_start, turn)

                    tools = tools_enabled && prompt_tools && !prompt_tools.empty? ? prompt_tools : nil
                    request_messages = messages.dup.freeze

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

                    llm_payload = {
                      run_id: run_id,
                      turn_number: turn,
                      model: model,
                      stream: false,
                      messages_count: request_messages.size,
                      tools_count: tools ? tools.size : 0,
                      options_summary: summarize_llm_options(options),
                    }

                    response =
                      instrumenter.instrument("agent_core.llm.call", llm_payload) do
                        resp =
                          provider.chat(
                            messages: request_messages,
                            model: model,
                            tools: tools,
                            stream: false,
                            **options
                          )
                        llm_payload[:stop_reason] = resp.stop_reason
                        llm_payload[:usage] = resp.usage&.to_h
                        resp
                      end

                    llm_trace =
                      LlmCallTrace.new(
                        model: model.to_s,
                        messages_count: request_messages.size,
                        tools_count: tools ? tools.size : 0,
                        options_summary: llm_payload.fetch(:options_summary),
                        stop_reason: llm_payload.fetch(:stop_reason, nil),
                        usage: llm_payload.fetch(:usage, nil),
                        duration_ms: llm_payload.fetch(:duration_ms, nil),
                      )

                    assistant_msg = response.message
                    turn_stop_reason = response.stop_reason
                    turn_usage_obj = response.usage

                    if response.usage
                      per_turn_usage << response.usage
                      aggregated_usage = aggregated_usage ? aggregated_usage + response.usage : response.usage
                    end

                    messages << assistant_msg
                    all_new_messages << assistant_msg
                    events.emit(:llm_response, response)

                    effective_max_tool_calls_per_turn =
                      if max_tool_calls_per_turn
                        limit = Integer(max_tool_calls_per_turn)
                        raise ArgumentError, "max_tool_calls_per_turn must be positive" if limit <= 0
                        limit
                      elsif options.fetch(:parallel_tool_calls, nil) == false
                        1
                      end

                    tool_calls = assistant_msg.tool_calls || []

                    if tools_registry && tools && effective_max_tool_calls_per_turn && tool_calls.size > effective_max_tool_calls_per_turn
                      ignored = tool_calls.drop(effective_max_tool_calls_per_turn)

                      ignored.each do |tc|
                        tool_calls_record << {
                          tool_call_id: tc.id,
                          name: tc.name,
                          arguments: tc.arguments,
                          error: "ignored: max_tool_calls_per_turn=#{effective_max_tool_calls_per_turn}",
                        }
                      end

                      tool_calls = tool_calls.first(effective_max_tool_calls_per_turn)

                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: tool_calls.empty? ? nil : tool_calls,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                      messages[-1] = assistant_msg
                      all_new_messages[-1] = assistant_msg
                    elsif tools.nil? && assistant_msg.has_tool_calls?
                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: nil,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                      tool_calls = []
                      messages[-1] = assistant_msg
                      all_new_messages[-1] = assistant_msg
                    end

                    any_tool_calls_seen ||= tool_calls.any? if tools_registry && tools

                    if tool_calls.any? && tools_registry && tools
                      tool_processing =
                        process_tool_calls_for_turn(
                          tool_calls: tool_calls,
                          tools_registry: tools_registry,
                          tool_policy: tool_policy,
                          tool_executor: tool_executor,
                          events: events,
                          tool_calls_record: tool_calls_record,
                          max_tool_output_bytes: max_tool_output_bytes,
                          turn_number: turn,
                          execution_context: execution_context,
                          stream_block: nil
                        )

                      tool_authorization_traces.concat(tool_processing.fetch(:authorization_traces))
                      tool_execution_traces.concat(tool_processing.fetch(:execution_traces))

                      Array(tool_processing[:result_messages]).each do |result_msg|
                        messages << result_msg
                        all_new_messages << result_msg
                      end

                      if tool_processing[:pause_state]
                        pause_state = tool_processing.fetch(:pause_state)
                        stop_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
                        turn_stop_reason = stop_reason
                        completed_turns = turn
                        run_payload[:stop_reason] = stop_reason
                        publish_pause_event(
                          instrumenter,
                          run_id: run_id,
                          turn_number: turn,
                          pause_state: pause_state,
                        )
                        events.emit(:turn_end, turn, all_new_messages)
                        next :stop
                      end

                      events.emit(:turn_end, turn, all_new_messages)
                      next :continue
                    end

                    if fix_empty_final &&
                        !empty_final_fixup_attempted &&
                        tools_registry &&
                        any_tool_calls_seen &&
                        assistant_msg.assistant? &&
                        assistant_msg.text.to_s.strip.empty?
                      empty_final_fixup_attempted = true
                      tools_enabled = false if fix_empty_final_disable_tools
                      events.emit(:turn_end, turn, all_new_messages)
                      user_msg = Message.new(role: :user, content: fix_empty_final_user_text)
                      messages << user_msg
                      all_new_messages << user_msg
                      next :continue
                    end

                    events.emit(:turn_end, turn, all_new_messages)
                    stop_reason = turn_stop_reason
                    completed_turns = turn
                    run_payload[:stop_reason] = stop_reason
                    :stop
                  ensure
                    turn_payload[:stop_reason] ||= turn_stop_reason
                    turn_payload[:usage] ||= turn_usage_obj&.to_h if turn_usage_obj
                  end
                end

            turn_ended_at = clock.now

            turn_traces <<
              TurnTrace.new(
                turn_number: turn,
                started_at: turn_started_at,
                ended_at: turn_ended_at,
                duration_ms: turn_payload.fetch(:duration_ms, nil),
                llm: llm_trace,
                tool_authorizations: tool_authorization_traces,
                tool_executions: tool_execution_traces,
                stop_reason: turn_stop_reason,
                usage: turn_usage_obj&.to_h,
              )

            break if turn_outcome == :stop
            end
          ensure
            run_payload[:turns] ||= completed_turns
            run_payload[:usage] ||= aggregated_usage&.to_h if aggregated_usage
          end
        end

        run_ended_at = clock.now
        segment_duration_ms = (clock.monotonic - run_started_mono) * 1000.0
        run_duration_ms = prior_duration_ms + segment_duration_ms

        run_trace =
          RunTrace.new(
            run_id: run_id,
            started_at: run_started_at,
            ended_at: run_ended_at,
            duration_ms: run_duration_ms,
            turns: turn_traces,
            stop_reason: stop_reason,
            usage: aggregated_usage&.to_h,
          )

        if pause_state
          ensure_pause_state_ids!(pause_state, parent_continuation_id: continuation&.continuation_id)

          pause_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
          pending_tool_confirmations =
            pause_reason == :awaiting_tool_confirmation ? pause_state.fetch(:pending_tool_confirmations) : []
          pending_tool_executions =
            pause_reason == :awaiting_tool_results ? pause_state.fetch(:pending_tool_executions) : []

          next_continuation =
            Continuation.new(
              run_id: run_id,
              continuation_id: normalize_optional_id(pause_state[:continuation_id]),
              parent_continuation_id: normalize_optional_id(pause_state[:parent_continuation_id]),
              started_at: run_started_at,
              duration_ms: run_duration_ms,
              turn: completed_turns,
              max_turns: max_turns,
              messages: messages.dup.freeze,
              model: model,
              options: options.dup.freeze,
              tools: prompt_tools,
              tools_enabled: tools_enabled,
              empty_final_fixup_attempted: empty_final_fixup_attempted,
              any_tool_calls_seen: any_tool_calls_seen,
              tool_calls_record: tool_calls_record.dup.freeze,
              aggregated_usage: aggregated_usage,
              per_turn_usage: per_turn_usage.dup.freeze,
              turn_traces: turn_traces.dup.freeze,
              pause_reason: pause_reason,
              pending_tool_calls: pause_state.fetch(:pending_tool_calls),
              pending_tool_executions: pending_tool_executions,
              buffered_tool_results: buffered_tool_results_for(pause_state),
              pending_decisions: pause_state.fetch(:pending_decisions),
              context_attributes: execution_context.attributes,
              max_tool_output_bytes: max_tool_output_bytes,
              max_tool_calls_per_turn: max_tool_calls_per_turn,
              fix_empty_final: fix_empty_final,
              fix_empty_final_user_text: fix_empty_final_user_text,
              fix_empty_final_disable_tools: fix_empty_final_disable_tools,
            )
        end

        build_result(
          run_id: run_id,
          started_at: run_started_at,
          ended_at: run_ended_at,
          duration_ms: run_duration_ms,
          trace: run_trace,
          all_new_messages: all_new_messages,
          turns: completed_turns,
          usage: aggregated_usage,
          tool_calls_record: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage,
          pending_tool_confirmations: pending_tool_confirmations,
          pending_tool_executions: pending_tool_executions,
          continuation: next_continuation,
        )
      end

      # Streaming variant of {#resume_with_tool_results}.
      #
      # @param continuation [Continuation, Hash, String] RunResult#continuation (or a ContinuationCodec payload)
      def resume_stream_with_tool_results(continuation:, tool_results:, provider:, tools_registry:, tool_policy: nil, events: nil,
                                          token_counter: nil, context_window: nil, reserved_output_tokens: 0,
                                          context: nil, instrumenter: nil, tool_executor: ToolExecutor::Inline.new, allow_partial: false, &block)
        continuation = coerce_continuation(continuation)

        if continuation.pause_reason != :awaiting_tool_results
          raise ArgumentError, "continuation pause_reason is #{continuation.pause_reason.inspect} (expected :awaiting_tool_results)"
        end

        pending_tool_executions = Array(continuation.pending_tool_executions)
        if pending_tool_executions.empty?
          raise ArgumentError, "continuation has no pending tool executions"
        end

        pending_tool_calls = Array(continuation.pending_tool_calls)
        if pending_tool_calls.empty?
          raise ArgumentError, "continuation has no pending tool calls"
        end

        buffered_tool_results =
          if continuation.respond_to?(:buffered_tool_results) && continuation.buffered_tool_results.is_a?(Hash)
            continuation.buffered_tool_results
          else
            {}
          end

        buffered_tool_results =
          buffered_tool_results.each_with_object({}) do |(tool_call_id, result), out|
            id = tool_call_id.to_s
            next if id.strip.empty?
            next unless result.is_a?(Resources::Tools::ToolResult)

            out[id] = result
          end

        allow_partial = allow_partial == true

        raise ArgumentError, "tool_results must be a Hash" unless tool_results.is_a?(Hash)

        raise ArgumentError, "provider is required" unless provider
        raise ArgumentError, "tools_registry is required" unless tools_registry

        events ||= Events.new

        base_context = context || continuation.context_attributes
        execution_context = ExecutionContext.from(base_context, instrumenter: instrumenter).with(run_id: continuation.run_id)
        instrumenter = execution_context.instrumenter
        clock = execution_context.clock
        run_id = execution_context.run_id

        publish_resume_event(
          instrumenter,
          run_id: run_id,
          paused_turn_number: continuation.turn,
          pause_reason: continuation.pause_reason,
          continuation_id: continuation.continuation_id,
        )

        messages = continuation.messages.dup
        tool_calls_record = continuation.tool_calls_record.dup
        aggregated_usage = continuation.aggregated_usage
        per_turn_usage = continuation.per_turn_usage.dup
        turn_traces = continuation.turn_traces.dup

        prompt_tools = continuation.tools
        options = continuation.options.dup
        model = continuation.model

        turn = continuation.turn
        max_turns = continuation.max_turns
        tools_enabled = continuation.tools_enabled
        empty_final_fixup_attempted = continuation.empty_final_fixup_attempted
        any_tool_calls_seen = continuation.any_tool_calls_seen

        fix_empty_final = continuation.fix_empty_final
        fix_empty_final_user_text = continuation.fix_empty_final_user_text.to_s
        fix_empty_final_disable_tools = continuation.fix_empty_final_disable_tools
        max_tool_output_bytes = continuation.max_tool_output_bytes
        max_tool_calls_per_turn = continuation.max_tool_calls_per_turn

        run_started_at = continuation.started_at
        prior_duration_ms = continuation.duration_ms.to_f
        run_started_mono = clock.monotonic

        all_new_messages = []
        pending_tool_confirmations = []
        next_continuation = nil
        pause_state = nil

        stop_reason = :end_turn
        completed_turns = turn

        run_payload = { run_id: run_id, resumed: true, stage: "tool_results", stream: true }

        instrumenter.instrument("agent_core.run", run_payload) do
          begin
            external_exec_traces = []

            normalized_tool_results = {}

            tool_results.each do |tool_call_id, result|
              id = tool_call_id.to_s
              raise ArgumentError, "tool_results contains blank tool_call_id" if id.strip.empty?
              raise ArgumentError, "tool_results contains duplicate tool_call_id=#{id}" if normalized_tool_results.key?(id)

              normalized_tool_results[id] = result
            end

            pending_by_id = pending_tool_executions.each_with_object({}) do |pending, out|
              out[pending.tool_call_id.to_s] = pending
            end

            allowed_ids = pending_by_id.keys.to_h { |id| [id, true] }
            buffered_tool_results.each_key { |id| allowed_ids[id.to_s] = true }

            normalized_tool_results.each_key do |id|
              next if allowed_ids.key?(id)

              raise ArgumentError, "Unexpected tool result for tool_call_id=#{id}"
            end

            unless allow_partial
              missing =
                pending_tool_executions
                  .map { |p| p.tool_call_id.to_s }
                  .reject { |id| buffered_tool_results.key?(id) || normalized_tool_results.key?(id) }

              raise ArgumentError, "Missing tool result for tool_call_id=#{missing.first}" if missing.any?
            end

            stream_block = block

            pending_tool_executions.each do |pending|
              tool_call_id = pending.tool_call_id.to_s
              result = normalized_tool_results[tool_call_id]
              next if result.nil?

              unless result.is_a?(Resources::Tools::ToolResult)
                raise ArgumentError, "tool_results[#{tool_call_id.inspect}] must be a ToolResult (got #{result.class})"
              end

              result =
                ToolExecutionUtils.limit_tool_result(
                  result,
                  max_bytes: max_tool_output_bytes,
                  tool_name: pending.executed_name
                )

              existing = buffered_tool_results[tool_call_id]
              if existing
                next if existing.to_h == result.to_h

                raise ArgumentError, "Conflicting tool result for tool_call_id=#{tool_call_id}"
              end

              buffered_tool_results[tool_call_id] = result

              stream_block&.call(StreamEvent::ToolExecutionStart.new(
                tool_call_id: tool_call_id,
                name: pending.name.to_s,
                arguments: pending.arguments,
              ))
              stream_block&.call(StreamEvent::ToolExecutionEnd.new(
                tool_call_id: tool_call_id,
                name: pending.name.to_s,
                result: result,
                error: result.error? == true,
              ))

              instrumenter.publish(
                "agent_core.tool.execute",
                {
                  run_id: run_id,
                  tool_call_id: tool_call_id,
                  name: pending.name.to_s,
                  executed_name: pending.executed_name.to_s,
                  source: pending.source.to_s,
                  stage: "external",
                  arguments_summary: pending.arguments_summary,
                  result_error: result.error?,
                  result_summary: ToolExecutionUtils.summarize_tool_result(result),
                  duration_ms: result.metadata.is_a?(Hash) ? result.metadata.fetch(:duration_ms, 0.0).to_f : 0.0,
                  turn_number: turn,
                }.compact
              )

              external_exec_traces <<
                ToolExecutionTrace.new(
                  tool_call_id: tool_call_id,
                  name: pending.name.to_s,
                  executed_name: pending.executed_name.to_s,
                  source: pending.source.to_s,
                  arguments_summary: pending.arguments_summary,
                  result_summary: ToolExecutionUtils.summarize_tool_result(result),
                  error: result.error? == true,
                  duration_ms: result.metadata.is_a?(Hash) ? result.metadata.fetch(:duration_ms, 0.0).to_f : 0.0,
                )

              tool_calls_record.each do |r|
                next unless r.is_a?(Hash) && r[:tool_call_id].to_s == tool_call_id

                r[:pending] = false
                r[:deferred] = false
                r[:external] = true
                r[:error] = result.error? ? result.text : nil
                break
              end

              events.emit(:tool_result, pending.name.to_s, result, tool_call_id)
            end

            normalized_tool_results.each do |tool_call_id, result|
              next if pending_by_id.key?(tool_call_id)

              existing = buffered_tool_results[tool_call_id]
              raise ArgumentError, "Unexpected tool result for tool_call_id=#{tool_call_id}" unless existing

              unless result.is_a?(Resources::Tools::ToolResult)
                raise ArgumentError, "tool_results[#{tool_call_id.inspect}] must be a ToolResult (got #{result.class})"
              end

              tool_name =
                tool_calls_record.find { |r| r.is_a?(Hash) && r[:tool_call_id].to_s == tool_call_id }&.fetch(:executed_name, nil).to_s
              tool_name = tool_call_id if tool_name.strip.empty?

              result = ToolExecutionUtils.limit_tool_result(result, max_bytes: max_tool_output_bytes, tool_name: tool_name)
              next if existing.to_h == result.to_h

              raise ArgumentError, "Conflicting tool result for tool_call_id=#{tool_call_id}"
            end

            apply_resume_tool_traces!(
              turn_traces: turn_traces,
              paused_turn_number: turn,
              confirmation_traces: [],
              execution_traces: external_exec_traces,
            )

            remaining =
              pending_tool_executions.reject do |pending|
                buffered_tool_results.key?(pending.tool_call_id.to_s)
              end

            if remaining.any?
              pause_state = {
                reason: :awaiting_tool_results,
                pending_tool_executions: remaining,
                pending_tool_calls: pending_tool_calls,
                pending_decisions: continuation.pending_decisions,
                buffered_tool_results: buffered_tool_results,
              }
              stop_reason = :awaiting_tool_results
              run_payload[:stop_reason] = stop_reason
              completed_turns = turn
              publish_pause_event(
                instrumenter,
                run_id: run_id,
                turn_number: turn,
                pause_state: pause_state,
                parent_continuation_id: continuation&.continuation_id,
              )
              yield StreamEvent::ToolExecutionRequired.new(run_id: run_id, pending_tool_executions: remaining) if block
              next
            end

            pending_tool_calls.each do |tc|
              tool_call_id = tc.id.to_s
              result = buffered_tool_results.fetch(tool_call_id) do
                raise ArgumentError, "Missing buffered tool result for tool_call_id=#{tool_call_id}"
              end

              tool_result_message =
                tool_result_to_message(
                  result,
                  tool_call_id: tool_call_id,
                  name: tc.name.to_s,
                  max_tool_output_bytes: max_tool_output_bytes,
                )

              messages << tool_result_message
              all_new_messages << tool_result_message
            end

            if turn >= max_turns
              completed_turns = turn
              stop_reason = :max_turns
              run_payload[:stop_reason] = stop_reason
              next
            end

            loop do
              turn += 1

              if turn > max_turns
                completed_turns = turn - 1
                stop_reason = :max_turns
                run_payload[:stop_reason] = stop_reason
                yield StreamEvent::ErrorEvent.new(error: "Max turns exceeded", recoverable: false) if block
                break
              end

              yield StreamEvent::TurnStart.new(turn_number: turn) if block
              events.emit(:turn_start, turn)

              turn_started_at = clock.now
              turn_payload = { run_id: run_id, turn_number: turn }

              tool_authorization_traces = []
              tool_execution_traces = []
              llm_trace = nil
              turn_stop_reason = :end_turn
              turn_usage_obj = nil

              turn_outcome =
                instrumenter.instrument("agent_core.turn", turn_payload) do
                  begin
                    tools = tools_enabled && prompt_tools && !prompt_tools.empty? ? prompt_tools : nil
                    request_messages = messages.dup.freeze

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

                    assistant_msg = nil
                    response_stop_reason = :end_turn
                    response_usage = nil

                    llm_payload = {
                      run_id: run_id,
                      turn_number: turn,
                      model: model,
                      stream: true,
                      messages_count: request_messages.size,
                      tools_count: tools ? tools.size : 0,
                      options_summary: summarize_llm_options(options),
                    }

                    instrumenter.instrument("agent_core.llm.call", llm_payload) do
                      stream_enum =
                        provider.chat(
                          messages: request_messages,
                          model: model,
                          tools: tools,
                          stream: true,
                          **options
                        )

                      stream_enum.each do |event|
                        events.emit(:stream_delta, event)

                        case event
                        when StreamEvent::Done
                          response_stop_reason = event.stop_reason
                          response_usage = event.usage
                          next
                        when StreamEvent::MessageComplete
                          assistant_msg = event.message
                        end

                        yield event if block
                      end

                      llm_payload[:stop_reason] = response_stop_reason
                      llm_payload[:usage] = response_usage&.to_h

                      nil
                    end

                    llm_trace =
                      LlmCallTrace.new(
                        model: model.to_s,
                        messages_count: request_messages.size,
                        tools_count: tools ? tools.size : 0,
                        options_summary: llm_payload.fetch(:options_summary),
                        stop_reason: llm_payload.fetch(:stop_reason, nil),
                        usage: llm_payload.fetch(:usage, nil),
                        duration_ms: llm_payload.fetch(:duration_ms, nil),
                      )

                    turn_stop_reason = response_stop_reason
                    turn_usage_obj = response_usage

                    if response_usage
                      per_turn_usage << response_usage
                      aggregated_usage = aggregated_usage ? aggregated_usage + response_usage : response_usage
                    end

                    unless assistant_msg
                      yield StreamEvent::ErrorEvent.new(
                        error: "Provider stream ended without producing a MessageComplete event",
                        recoverable: false
                      ) if block
                      stop_reason = :error
                      completed_turns = turn
                      run_payload[:stop_reason] = stop_reason
                      events.emit(:turn_end, turn, all_new_messages)
                      next :stop
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

                    effective_max_tool_calls_per_turn =
                      if max_tool_calls_per_turn
                        limit = Integer(max_tool_calls_per_turn)
                        raise ArgumentError, "max_tool_calls_per_turn must be positive" if limit <= 0
                        limit
                      elsif options.fetch(:parallel_tool_calls, nil) == false
                        1
                      end

                    tool_calls = assistant_msg.tool_calls || []

                    if tools_registry && tools && effective_max_tool_calls_per_turn && tool_calls.size > effective_max_tool_calls_per_turn
                      ignored = tool_calls.drop(effective_max_tool_calls_per_turn)

                      ignored.each do |tc|
                        tool_calls_record << {
                          tool_call_id: tc.id,
                          name: tc.name,
                          arguments: tc.arguments,
                          error: "ignored: max_tool_calls_per_turn=#{effective_max_tool_calls_per_turn}",
                        }
                      end

                      tool_calls = tool_calls.first(effective_max_tool_calls_per_turn)

                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: tool_calls.empty? ? nil : tool_calls,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                      messages[-1] = assistant_msg
                      all_new_messages[-1] = assistant_msg
                    elsif tools.nil? && assistant_msg.has_tool_calls?
                      assistant_msg =
                        Message.new(
                          role: assistant_msg.role,
                          content: assistant_msg.content,
                          tool_calls: nil,
                          tool_call_id: assistant_msg.tool_call_id,
                          name: assistant_msg.name,
                          metadata: assistant_msg.metadata,
                        )
                      tool_calls = []
                      messages[-1] = assistant_msg
                      all_new_messages[-1] = assistant_msg
                    end

                    any_tool_calls_seen ||= tool_calls.any? if tools_registry && tools

                    if tool_calls.any? && tools_registry && tools
                      tool_processing =
                        process_tool_calls_for_turn(
                          tool_calls: tool_calls,
                          tools_registry: tools_registry,
                          tool_policy: tool_policy,
                          tool_executor: tool_executor,
                          events: events,
                          tool_calls_record: tool_calls_record,
                          max_tool_output_bytes: max_tool_output_bytes,
                          turn_number: turn,
                          execution_context: execution_context,
                          stream_block: block
                        )

                      tool_authorization_traces.concat(tool_processing.fetch(:authorization_traces))
                      tool_execution_traces.concat(tool_processing.fetch(:execution_traces))

                      Array(tool_processing[:result_messages]).each do |result_msg|
                        messages << result_msg
                        all_new_messages << result_msg
                      end

                      yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg, stop_reason: response_stop_reason, usage: response_usage) if block
                      events.emit(:turn_end, turn, all_new_messages)

                      if tool_processing[:pause_state]
                        pause_state = tool_processing.fetch(:pause_state)
                        stop_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
                        turn_stop_reason = stop_reason
                        completed_turns = turn
                        run_payload[:stop_reason] = stop_reason
                        publish_pause_event(
                          instrumenter,
                          run_id: run_id,
                          turn_number: turn,
                          pause_state: pause_state,
                        )

                        case stop_reason
                        when :awaiting_tool_confirmation
                          yield StreamEvent::AuthorizationRequired.new(
                            run_id: run_id,
                            pending_tool_confirmations: pause_state.fetch(:pending_tool_confirmations),
                          ) if block
                        when :awaiting_tool_results
                          yield StreamEvent::ToolExecutionRequired.new(
                            run_id: run_id,
                            pending_tool_executions: pause_state.fetch(:pending_tool_executions),
                          ) if block
                        end
                        next :stop
                      end

                      next :continue
                    end

                    if fix_empty_final &&
                        !empty_final_fixup_attempted &&
                        tools_registry &&
                        any_tool_calls_seen &&
                        assistant_msg.assistant? &&
                        assistant_msg.text.to_s.strip.empty?
                      empty_final_fixup_attempted = true
                      tools_enabled = false if fix_empty_final_disable_tools
                      yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg, stop_reason: response_stop_reason, usage: response_usage) if block
                      events.emit(:turn_end, turn, all_new_messages)
                      user_msg = Message.new(role: :user, content: fix_empty_final_user_text)
                      messages << user_msg
                      all_new_messages << user_msg
                      next :continue
                    end

                    yield StreamEvent::TurnEnd.new(turn_number: turn, message: assistant_msg, stop_reason: response_stop_reason, usage: response_usage) if block
                    events.emit(:turn_end, turn, all_new_messages)

                    stop_reason = response_stop_reason
                    completed_turns = turn
                    run_payload[:stop_reason] = stop_reason
                    :stop
                  ensure
                    turn_payload[:stop_reason] ||= turn_stop_reason
                    turn_payload[:usage] ||= turn_usage_obj&.to_h if turn_usage_obj
                  end
                end

              turn_ended_at = clock.now
              turn_traces <<
                TurnTrace.new(
                  turn_number: turn,
                  started_at: turn_started_at,
                  ended_at: turn_ended_at,
                  duration_ms: turn_payload.fetch(:duration_ms, nil),
                  llm: llm_trace,
                  tool_authorizations: tool_authorization_traces,
                  tool_executions: tool_execution_traces,
                  stop_reason: turn_stop_reason,
                  usage: turn_usage_obj&.to_h,
                )

              break if turn_outcome == :stop
            end
          ensure
            run_payload[:turns] ||= completed_turns
            run_payload[:usage] ||= aggregated_usage&.to_h if aggregated_usage
          end
        end

        run_ended_at = clock.now
        segment_duration_ms = (clock.monotonic - run_started_mono) * 1000.0
        run_duration_ms = prior_duration_ms + segment_duration_ms

        run_trace =
          RunTrace.new(
            run_id: run_id,
            started_at: run_started_at,
            ended_at: run_ended_at,
            duration_ms: run_duration_ms,
            turns: turn_traces,
            stop_reason: stop_reason,
            usage: aggregated_usage&.to_h,
          )

        yield StreamEvent::Done.new(stop_reason: stop_reason, usage: aggregated_usage) if block

        if pause_state
          ensure_pause_state_ids!(pause_state, parent_continuation_id: continuation&.continuation_id)

          pause_reason = pause_state.fetch(:reason, :awaiting_tool_confirmation)
          pending_tool_confirmations =
            pause_reason == :awaiting_tool_confirmation ? pause_state.fetch(:pending_tool_confirmations) : []
          pending_tool_executions =
            pause_reason == :awaiting_tool_results ? pause_state.fetch(:pending_tool_executions) : []

          next_continuation =
            Continuation.new(
              run_id: run_id,
              continuation_id: normalize_optional_id(pause_state[:continuation_id]),
              parent_continuation_id: normalize_optional_id(pause_state[:parent_continuation_id]),
              started_at: run_started_at,
              duration_ms: run_duration_ms,
              turn: completed_turns,
              max_turns: max_turns,
              messages: messages.dup.freeze,
              model: model,
              options: options.dup.freeze,
              tools: prompt_tools,
              tools_enabled: tools_enabled,
              empty_final_fixup_attempted: empty_final_fixup_attempted,
              any_tool_calls_seen: any_tool_calls_seen,
              tool_calls_record: tool_calls_record.dup.freeze,
              aggregated_usage: aggregated_usage,
              per_turn_usage: per_turn_usage.dup.freeze,
              turn_traces: turn_traces.dup.freeze,
              pause_reason: pause_reason,
              pending_tool_calls: pause_state.fetch(:pending_tool_calls),
              pending_tool_executions: pending_tool_executions,
              buffered_tool_results: buffered_tool_results_for(pause_state),
              pending_decisions: pause_state.fetch(:pending_decisions),
              context_attributes: execution_context.attributes,
              max_tool_output_bytes: max_tool_output_bytes,
              max_tool_calls_per_turn: max_tool_calls_per_turn,
              fix_empty_final: fix_empty_final,
              fix_empty_final_user_text: fix_empty_final_user_text,
              fix_empty_final_disable_tools: fix_empty_final_disable_tools,
            )
        end

        build_result(
          run_id: run_id,
          started_at: run_started_at,
          ended_at: run_ended_at,
          duration_ms: run_duration_ms,
          trace: run_trace,
          all_new_messages: all_new_messages,
          turns: completed_turns,
          usage: aggregated_usage,
          tool_calls_record: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage,
          pending_tool_confirmations: pending_tool_confirmations,
          pending_tool_executions: pending_tool_executions,
          continuation: next_continuation,
        )
      end

      private

      def coerce_continuation(value)
        return value if value.is_a?(Continuation)
        return ContinuationCodec.load(value) if value.is_a?(Hash) || value.is_a?(String)

        raise ArgumentError, "continuation must be a PromptRunner::Continuation, Hash, or JSON String (got #{value.class})"
      end

      def normalize_optional_id(value)
        id = value.to_s.strip
        id.empty? ? nil : id
      end

      def ensure_pause_state_ids!(pause_state, parent_continuation_id: nil)
        state = pause_state.is_a?(Hash) ? pause_state : {}

        cid = normalize_optional_id(state[:continuation_id])
        state[:continuation_id] = cid || SecureRandom.uuid

        pid = normalize_optional_id(state[:parent_continuation_id])
        pid ||= normalize_optional_id(parent_continuation_id)
        state[:parent_continuation_id] = pid if pid

        state
      rescue StandardError
        pause_state
      end

      def buffered_tool_results_for(pause_state)
        state = pause_state.is_a?(Hash) ? pause_state : {}
        raw = state.fetch(:buffered_tool_results, {})
        h = raw.is_a?(Hash) ? raw : {}
        h.dup.freeze
      rescue StandardError
        {}.freeze
      end

      def publish_pause_event(instrumenter, run_id:, turn_number:, pause_state:, parent_continuation_id: nil)
        state = pause_state.is_a?(Hash) ? pause_state : {}
        ensure_pause_state_ids!(state, parent_continuation_id: parent_continuation_id)

        continuation_id = normalize_optional_id(state[:continuation_id])
        parent_continuation_id = normalize_optional_id(state[:parent_continuation_id])
        reason = state.fetch(:reason, :awaiting_tool_confirmation)

        pending_confirmations_count =
          reason == :awaiting_tool_confirmation ? Array(state[:pending_tool_confirmations]).size : 0
        pending_executions_count =
          reason == :awaiting_tool_results ? Array(state[:pending_tool_executions]).size : 0

        instrumenter.publish(
          "agent_core.pause",
          {
            run_id: run_id.to_s,
            turn_number: Integer(turn_number),
            pause_reason: reason.to_s,
            continuation_id: continuation_id,
            parent_continuation_id: parent_continuation_id,
            pending_confirmations_count: pending_confirmations_count,
            pending_executions_count: pending_executions_count,
            duration_ms: 0.0,
          }.compact
        )
      end

      def publish_resume_event(instrumenter, run_id:, paused_turn_number:, pause_reason:, continuation_id: nil)
        continuation_id = normalize_optional_id(continuation_id)

        instrumenter.publish(
          "agent_core.resume",
          {
            run_id: run_id.to_s,
            paused_turn_number: Integer(paused_turn_number),
            pause_reason: pause_reason.to_s,
            continuation_id: continuation_id,
            resumed: true,
            duration_ms: 0.0,
          }.compact
        )
      end

      # Process tool calls for a single turn.
      #
      # Returns:
      # - result_messages: tool result messages generated immediately (invalid args / executed tools)
      # - authorization_traces: ToolAuthorizationTrace[]
      # - execution_traces: ToolExecutionTrace[]
      # - pause_state: nil or { pending_tool_confirmations:, pending_tool_calls:, pending_decisions: }
      def process_tool_calls_for_turn(tool_calls:, tools_registry:, tool_policy:, tool_executor:, events:, tool_calls_record:, max_tool_output_bytes:,
                                      turn_number:, execution_context:, stream_block: nil)
        instrumenter = execution_context.instrumenter
        run_id = execution_context.run_id
        turn_number_i = Integer(turn_number)

        authorization_traces = []
        execution_traces = []
        result_messages = []
        args_summaries = {}
        valid_tool_calls = []

        tool_calls.each do |tc|
          events.emit(:tool_call, tc.name, tc.arguments, tc.id)

          args_summary = args_summaries[tc.id] = ToolExecutionUtils.summarize_tool_arguments(tc.arguments)

          arguments_valid = tc.respond_to?(:arguments_valid?) ? tc.arguments_valid? : true
          parse_error = tc.respond_to?(:arguments_parse_error) ? tc.arguments_parse_error : nil

          instrumenter.publish(
            "agent_core.tool.task.created",
            {
              run_id: run_id.to_s,
              turn_number: turn_number_i,
              tool_call_id: tc.id.to_s,
              name: tc.name.to_s,
              arguments_summary: args_summary,
              arguments_valid: arguments_valid,
              arguments_parse_error: parse_error.nil? ? nil : parse_error.to_s,
              duration_ms: 0.0,
            }.compact
          )

          if tc.respond_to?(:arguments_valid?) && !tc.arguments_valid?
            stream_block&.call(StreamEvent::ToolExecutionStart.new(
              tool_call_id: tc.id, name: tc.name, arguments: tc.arguments
            ))

            parse_error = tc.respond_to?(:arguments_parse_error) ? tc.arguments_parse_error : :invalid_json
            error_text =
              case parse_error
              when :too_large
                "Tool call arguments are too large. Retry with smaller arguments."
              else
                "Invalid JSON in tool call arguments. Retry with arguments as a JSON object only."
              end
            error_result = Resources::Tools::ToolResult.error(text: error_text)

            exec_payload = {
              run_id: run_id,
              tool_call_id: tc.id,
              name: tc.name,
              executed_name: tc.name,
              source: "runner",
              arguments_summary: args_summary,
            }

            instrumenter.instrument("agent_core.tool.execute", exec_payload) do
              exec_payload[:result_error] = true
              exec_payload[:result_summary] = ToolExecutionUtils.summarize_tool_result(error_result)
              error_result
            end

            execution_traces <<
              ToolExecutionTrace.new(
                tool_call_id: tc.id,
                name: tc.name,
                executed_name: tc.name,
                source: "runner",
                arguments_summary: args_summary,
                result_summary: exec_payload[:result_summary],
                error: true,
                duration_ms: exec_payload[:duration_ms],
              )

            stream_block&.call(StreamEvent::ToolExecutionEnd.new(
              tool_call_id: tc.id, name: tc.name, result: error_result, error: true
            ))
            events.emit(:tool_result, tc.name, error_result, tc.id)
            tool_calls_record << { name: tc.name, arguments: tc.arguments, error: parse_error.to_s }

            result_messages <<
              tool_result_to_message(
                error_result,
                tool_call_id: tc.id,
                name: tc.name,
                max_tool_output_bytes: max_tool_output_bytes,
              )
            next
          end

          valid_tool_calls << tc
        end

        decisions = {}
        pending_confirmations = []

        if valid_tool_calls.any?
          decisions, auth_traces, pending_confirmations =
            authorize_tool_calls(
              tool_calls: valid_tool_calls,
              tools_registry: tools_registry,
              tool_policy: tool_policy,
              execution_context: execution_context,
              args_summaries: args_summaries,
            )
          authorization_traces.concat(auth_traces)
        end

        if pending_confirmations.any?
          valid_tool_calls.each do |tc|
            d = decisions.fetch(tc.id)
            requested_name = tc.name.to_s
            executed_name =
              if tools_registry
                resolve_executed_tool_name(tools_registry, requested_name)
              else
                requested_name
              end
            tool_calls_record << {
              name: requested_name,
              executed_name: executed_name,
              arguments: tc.arguments,
              pending: true,
              outcome: d.outcome,
              reason: d.reason,
            }
          end

          return {
            result_messages: result_messages,
            authorization_traces: authorization_traces,
            execution_traces: execution_traces,
            pause_state: {
              reason: :awaiting_tool_confirmation,
              pending_tool_confirmations: pending_confirmations,
              pending_tool_calls: valid_tool_calls,
              pending_tool_executions: [],
              pending_decisions: decisions,
            },
          }
        end

        if valid_tool_calls.any?
          tool_result_messages, exec_traces, exec_pause_state =
            execute_tool_calls_with_decisions(
              tool_calls: valid_tool_calls,
              decisions: decisions,
              tools_registry: tools_registry,
              tool_executor: tool_executor,
              events: events,
              tool_calls_record: tool_calls_record,
              max_tool_output_bytes: max_tool_output_bytes,
              turn_number: turn_number,
              execution_context: execution_context,
              stream_block: stream_block,
              args_summaries: args_summaries,
            )

          execution_traces.concat(exec_traces)
          result_messages.concat(tool_result_messages)

          if exec_pause_state
            return {
              result_messages: result_messages,
              authorization_traces: authorization_traces,
              execution_traces: execution_traces,
              pause_state: exec_pause_state,
            }
          end
        end

        {
          result_messages: result_messages,
          authorization_traces: authorization_traces,
          execution_traces: execution_traces,
          pause_state: nil,
        }
      end

      def authorize_tool_calls(tool_calls:, tools_registry:, tool_policy:, execution_context:, args_summaries:)
        instrumenter = execution_context.instrumenter
        run_id = execution_context.run_id

        decisions = {}
        authorization_traces = []
        pending_confirmations = []

        tool_calls.each do |tc|
          requested_name = tc.name.to_s
          executed_name =
            if tools_registry
              resolve_executed_tool_name(tools_registry, requested_name)
            else
              requested_name
            end
          args_summary = args_summaries[tc.id] || ToolExecutionUtils.summarize_tool_arguments(tc.arguments)

          auth_payload = {
            run_id: run_id,
            tool_call_id: tc.id,
            name: requested_name,
            executed_name: executed_name,
            arguments_summary: args_summary,
          }

          decision =
            instrumenter.instrument("agent_core.tool.authorize", auth_payload) do
              d =
                begin
                  if tool_policy
                    tool_policy.authorize(name: executed_name, arguments: tc.arguments, context: execution_context)
                  else
                    Resources::Tools::Policy::Decision.deny(reason: "tool_policy is required")
                  end
                rescue StandardError => e
                  Resources::Tools::Policy::Decision.deny(reason: "tool_policy error: #{e.class}")
                end

              auth_payload[:outcome] = d.outcome
              auth_payload[:reason] = d.reason
              d
            end

          decisions[tc.id] = decision

          authorization_traces <<
            ToolAuthorizationTrace.new(
              tool_call_id: tc.id,
              name: requested_name,
              outcome: decision.outcome,
              reason: decision.reason,
              duration_ms: auth_payload[:duration_ms],
            )

          if decision.requires_confirmation?
            pending_confirmations <<
              PendingToolConfirmation.new(
                tool_call_id: tc.id,
                name: requested_name,
                arguments: tc.arguments,
                reason: decision.reason,
                arguments_summary: args_summary,
              )
          end
        end

        [decisions, authorization_traces, pending_confirmations]
      end

      def execute_tool_calls_with_decisions(tool_calls:, decisions:, tools_registry:, tool_executor:, events:, tool_calls_record:, max_tool_output_bytes:,
                                            turn_number:, execution_context:, stream_block:, args_summaries:)
        instrumenter = execution_context.instrumenter
        run_id = execution_context.run_id

        execution_traces = []
        result_messages = []

        allow_requests = []
        allow_tool_calls = []
        allow_requests_by_id = {}

        tool_calls.each do |tc|
          args_summary = args_summaries[tc.id] || ToolExecutionUtils.summarize_tool_arguments(tc.arguments)
          decision = decisions.fetch(tc.id)

          unless decision.allowed?
            stream_block&.call(StreamEvent::ToolExecutionStart.new(
              tool_call_id: tc.id, name: tc.name, arguments: tc.arguments
            ))

            error_result = Resources::Tools::ToolResult.error(
              text: "Tool call denied: #{decision.reason}"
            )

            exec_payload = {
              run_id: run_id,
              tool_call_id: tc.id,
              name: tc.name,
              executed_name: tc.name,
              source: "policy",
              arguments_summary: args_summary,
            }

            instrumenter.instrument("agent_core.tool.execute", exec_payload) do
              exec_payload[:result_error] = true
              exec_payload[:result_summary] = ToolExecutionUtils.summarize_tool_result(error_result)
              error_result
            end

            execution_traces <<
              ToolExecutionTrace.new(
                tool_call_id: tc.id,
                name: tc.name,
                executed_name: tc.name,
                source: "policy",
                arguments_summary: args_summary,
                result_summary: exec_payload[:result_summary],
                error: true,
                duration_ms: exec_payload[:duration_ms],
              )

            stream_block&.call(StreamEvent::ToolExecutionEnd.new(
              tool_call_id: tc.id, name: tc.name, result: error_result, error: true
            ))
            events.emit(:tool_result, tc.name, error_result, tc.id)
            tool_calls_record << { name: tc.name, arguments: tc.arguments, error: decision.reason }

            result_messages <<
              tool_result_to_message(
                error_result,
                tool_call_id: tc.id,
                name: tc.name,
                max_tool_output_bytes: max_tool_output_bytes,
              )
            next
          end

          requested_name = tc.name.to_s
          executed_name = resolve_executed_tool_name(tools_registry, requested_name)

          unless tools_registry.include?(executed_name)
            stream_block&.call(StreamEvent::ToolExecutionStart.new(
              tool_call_id: tc.id, name: tc.name, arguments: tc.arguments
            ))

            error_result = Resources::Tools::ToolResult.error(
              text: "Tool not found: #{requested_name}"
            )

            source = tool_source_for_registry(tools_registry, executed_name)
            exec_payload = {
              run_id: run_id,
              tool_call_id: tc.id,
              name: requested_name,
              executed_name: executed_name,
              source: source,
              arguments_summary: args_summary,
            }

            instrumenter.instrument("agent_core.tool.execute", exec_payload) do
              exec_payload[:result_error] = true
              exec_payload[:result_summary] = ToolExecutionUtils.summarize_tool_result(error_result)
              error_result
            end

            execution_traces <<
              ToolExecutionTrace.new(
                tool_call_id: tc.id,
                name: requested_name,
                executed_name: executed_name,
                source: source,
                arguments_summary: args_summary,
                result_summary: exec_payload[:result_summary],
                error: true,
                duration_ms: exec_payload[:duration_ms],
              )

            stream_block&.call(StreamEvent::ToolExecutionEnd.new(
              tool_call_id: tc.id, name: tc.name, result: error_result, error: true
            ))
            events.emit(:tool_result, tc.name, error_result, tc.id)
            tool_calls_record << { name: requested_name, executed_name: executed_name, arguments: tc.arguments, error: error_result.text }

            result_messages <<
              tool_result_to_message(
                error_result,
                tool_call_id: tc.id,
                name: requested_name,
                max_tool_output_bytes: max_tool_output_bytes,
              )
            next
          end

          source = tool_source_for_registry(tools_registry, executed_name)

          req =
            ToolExecutor::ExecutionRequest.new(
              tool_call_id: tc.id,
              name: requested_name,
              executed_name: executed_name,
              arguments: tc.arguments,
              arguments_summary: args_summary,
              source: source,
            )

          allow_requests << req
          allow_tool_calls << tc
          allow_requests_by_id[tc.id] = req
        end

        return [result_messages, execution_traces, nil] if allow_requests.empty?

        if stream_block && !(tool_executor.respond_to?(:deferred?) && tool_executor.deferred?)
          allow_requests.each do |req|
            stream_block.call(StreamEvent::ToolExecutionStart.new(
              tool_call_id: req.tool_call_id, name: req.name, arguments: req.arguments
            ))
          end
        end

        exec_result =
          tool_executor.execute(
            requests: allow_requests,
            tools_registry: tools_registry,
            execution_context: execution_context,
            max_tool_output_bytes: max_tool_output_bytes,
          )

        completed = exec_result.respond_to?(:completed) ? Array(exec_result.completed) : []
        deferred = exec_result.respond_to?(:deferred) ? Array(exec_result.deferred) : []

        if deferred.any?
          if completed.any?
            raise ArgumentError, "ToolExecutor returned both completed and deferred results (unsupported)"
          end

          executor_name = tool_executor.class.name.to_s

          deferred.each do |pending|
            source = pending.source.to_s
            source = nil if source.strip.empty?

            instrumenter.publish(
              "agent_core.tool.task.deferred",
              {
                run_id: run_id.to_s,
                turn_number: Integer(turn_number),
                tool_call_id: pending.tool_call_id.to_s,
                name: pending.name.to_s,
                executed_name: pending.executed_name.to_s,
                source: source,
                arguments_summary: pending.arguments_summary,
                executor: executor_name,
                duration_ms: 0.0,
              }.compact
            )

            tool_calls_record << {
              tool_call_id: pending.tool_call_id,
              name: pending.name,
              executed_name: pending.executed_name,
              arguments: pending.arguments,
              pending: true,
              deferred: true,
              outcome: :allow,
              reason: "deferred tool execution",
            }
          end

          return [
            result_messages,
            execution_traces,
            {
              reason: :awaiting_tool_results,
              pending_tool_executions: deferred,
              pending_tool_calls: allow_tool_calls,
              pending_decisions: decisions,
            },
          ]
        end

        completed_by_id = {}
        completed.each { |ce| completed_by_id[ce.tool_call_id] = ce }

        ordered_completed =
          allow_requests.map do |req|
            completed_by_id.fetch(req.tool_call_id)
          end

        ordered_completed.each do |ce|
          req = allow_requests_by_id.fetch(ce.tool_call_id)

          if stream_block && !(tool_executor.respond_to?(:deferred?) && tool_executor.deferred?)
            stream_block.call(StreamEvent::ToolExecutionEnd.new(
              tool_call_id: ce.tool_call_id, name: ce.name, result: ce.result, error: ce.error?
            ))
          end

          execution_traces <<
            ToolExecutionTrace.new(
              tool_call_id: ce.tool_call_id,
              name: ce.name,
              executed_name: ce.executed_name,
              source: ce.source,
              arguments_summary: req.arguments_summary,
              result_summary: ce.result_summary,
              error: ce.error? == true,
              duration_ms: ce.duration_ms,
            )

          events.emit(:tool_result, ce.name, ce.result, ce.tool_call_id)
          tool_calls_record << {
            name: ce.name,
            executed_name: ce.executed_name,
            arguments: req.arguments,
            error: ce.result.error? ? ce.result.text : nil,
          }

          result_messages <<
            tool_result_to_message(
              ce.result,
              tool_call_id: ce.tool_call_id,
              name: ce.name,
              max_tool_output_bytes: max_tool_output_bytes,
            )
        end

        [result_messages, execution_traces, nil]
      end

      def resolve_pending_tool_confirmations(pending_tool_calls:, pending_decisions:, tool_confirmations:)
        tool_confirmations = tool_confirmations.is_a?(Hash) ? tool_confirmations : {}
        pending_decisions = pending_decisions.is_a?(Hash) ? pending_decisions : {}

        resolved = {}
        confirmation_traces = []

        pending_tool_calls.each do |tc|
          decision = pending_decisions.fetch(tc.id)

          unless decision.respond_to?(:requires_confirmation?) && decision.respond_to?(:allowed?) && decision.respond_to?(:denied?)
            raise ArgumentError, "Invalid pending decision for tool_call_id=#{tc.id}"
          end

          unless decision.requires_confirmation?
            resolved[tc.id] = decision
            next
          end

          outcome = tool_confirmations.fetch(tc.id) do
            raise ArgumentError, "Missing tool confirmation for tool_call_id=#{tc.id}"
          end

          resolved_decision =
            case normalize_tool_confirmation(outcome)
            when :allow
              Resources::Tools::Policy::Decision.allow(reason: "confirmed by user")
            when :deny
              Resources::Tools::Policy::Decision.deny(reason: "denied by user")
            end

          resolved[tc.id] = resolved_decision

          confirmation_traces <<
            ToolAuthorizationTrace.new(
              tool_call_id: tc.id,
              name: tc.name,
              outcome: resolved_decision.outcome,
              reason: resolved_decision.reason,
              duration_ms: nil,
            )
        end

        [resolved, confirmation_traces]
      end

      def normalize_tool_confirmation(value)
        case value
        when true, :allow, "allow"
          :allow
        when false, :deny, "deny"
          :deny
        else
          raise ArgumentError, "Invalid tool confirmation: #{value.inspect} (expected :allow/:deny or true/false)"
        end
      end

      def publish_confirmation_authorizations!(instrumenter:, run_id:, paused_turn_number:, pending_tool_calls:, confirmation_traces:, resumed:,
                                               tools_registry: nil)
        return nil if confirmation_traces.nil? || confirmation_traces.empty?
        return nil unless instrumenter&.respond_to?(:publish)

        tool_by_id = {}
        Array(pending_tool_calls).each do |tc|
          tool_by_id[tc.id] = tc if tc.respond_to?(:id)
        end

        Array(confirmation_traces).each do |trace|
          next unless trace.respond_to?(:tool_call_id) && trace.respond_to?(:name)

          tc = tool_by_id[trace.tool_call_id]
          executed_name =
            if tc && tools_registry
              resolve_executed_tool_name(tools_registry, tc.name.to_s)
            else
              nil
            end
          args_summary = tc ? ToolExecutionUtils.summarize_tool_arguments(tc.arguments) : nil

          payload = {
            run_id: run_id,
            tool_call_id: trace.tool_call_id,
            name: trace.name.to_s,
            executed_name: executed_name,
            arguments_summary: args_summary,
            outcome: trace.outcome,
            reason: trace.reason,
            stage: "confirmation",
            resumed: resumed == true,
            turn_number: paused_turn_number,
            duration_ms: 0.0,
          }.compact

          instrumenter.publish("agent_core.tool.authorize", payload)
        end

        nil
      rescue StandardError
        nil
      end

      def apply_resume_tool_traces!(turn_traces:, paused_turn_number:, confirmation_traces:, execution_traces:)
        idx = turn_traces.rindex { |t| t.respond_to?(:turn_number) && t.turn_number == paused_turn_number }
        return false unless idx

        old = turn_traces[idx]
        old_auth = old.tool_authorizations || []
        old_exec = old.tool_executions || []

        turn_traces[idx] =
          old.with(
            tool_authorizations: old_auth + Array(confirmation_traces),
            tool_executions: old_exec + Array(execution_traces),
          )

        true
      rescue StandardError
        false
      end

      def build_result(
        run_id:,
        started_at:,
        ended_at:,
        duration_ms:,
        trace:,
        all_new_messages:,
        turns:,
        usage:,
        tool_calls_record:,
        stop_reason:,
        per_turn_usage: [],
        pending_tool_confirmations: [],
        pending_tool_executions: [],
        continuation: nil
      )
        final = all_new_messages.reverse.find { |m| m.assistant? } || all_new_messages.last

        RunResult.new(
          run_id: run_id,
          started_at: started_at,
          ended_at: ended_at,
          duration_ms: duration_ms,
          messages: all_new_messages,
          final_message: final,
          turns: turns,
          usage: usage,
          tool_calls_made: tool_calls_record,
          stop_reason: stop_reason,
          per_turn_usage: per_turn_usage,
          trace: trace,
          pending_tool_confirmations: pending_tool_confirmations,
          pending_tool_executions: pending_tool_executions,
          continuation: continuation,
        )
      end

      SAFE_LLM_OPTION_KEYS =
        %i[
          temperature
          max_tokens
          top_p
          stop_sequences
          parallel_tool_calls
          response_format
          stream_options
        ].freeze

      def summarize_llm_options(options)
        h = options.is_a?(Hash) ? options : {}
        out = {}

        SAFE_LLM_OPTION_KEYS.each do |key|
          next unless h.key?(key)
          out[key.to_s] = trace_sanitize(h[key], depth: 0)
        end

        out
      end

      def tool_source_for_registry(registry, name)
        info = registry.respond_to?(:find) ? registry.find(name) : nil
        case info
        when Resources::Tools::Tool
          meta = info.metadata
          source = meta.is_a?(Hash) ? meta[:source] : nil
          source ? source.to_s : "native"
        when Hash then "mcp"
        else "unknown"
        end
      rescue StandardError
        "unknown"
      end

      def resolve_executed_tool_name(registry, requested_name)
        execute_name = requested_name.to_s
        return execute_name if registry.include?(execute_name)

        if execute_name.include?(".")
          underscored = execute_name.tr(".", "_")
          return underscored if registry.include?(underscored)
        end

        execute_name
      rescue StandardError
        requested_name.to_s
      end

      def trace_sanitize(value, depth:)
        return "[max_depth]" if depth >= 6

        case value
        when nil, true, false, Integer, Float
          value
        when Symbol
          value.to_s
        when String
          Utils.truncate_utf8_bytes(value, max_bytes: 1_000)
        when Array
          value.first(50).map { |v| trace_sanitize(v, depth: depth + 1) }
        when Hash
          out = {}
          value.each_with_index do |(k, v), idx|
            break if idx >= 50
            out[k.to_s] = trace_sanitize(v, depth: depth + 1)
          end
          out
        else
          Utils.truncate_utf8_bytes(value.to_s, max_bytes: 1_000)
        end
      rescue StandardError
        value.to_s
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

      # Convert a ToolResult to a Message, preserving multimodal content blocks.
      #
      # When the result contains only text blocks, uses a simple String content
      # (backward compatible). When it contains images or other media, uses an
      # Array of ContentBlock objects so providers can serialize them correctly.
      def tool_result_to_message(result, tool_call_id:, name:, max_tool_output_bytes:)
        content_blocks = nil
        conversion_error = nil

        if result.has_non_text_content?
          begin
            content_blocks = result.to_content_blocks
          rescue => e
            conversion_error = e
          end
        end

        content = if content_blocks
          content_blocks
        elsif conversion_error
          fallback_text = result.text
          prefix = "Tool '#{name}' returned invalid multimodal content: #{conversion_error.message}"
          fallback_text.empty? ? prefix : "#{prefix}\n\n#{fallback_text}"
        else
          result.text
        end

        if content.is_a?(String) && content.bytesize > max_tool_output_bytes
          content = Utils.truncate_utf8_bytes(content, max_bytes: max_tool_output_bytes)
        end

        error = conversion_error ? true : result.error?

        Message.new(
          role: :tool_result, content: content,
          tool_call_id: tool_call_id, name: name,
          metadata: { error: error }
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
