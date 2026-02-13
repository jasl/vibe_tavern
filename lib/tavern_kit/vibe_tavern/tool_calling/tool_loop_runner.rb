# frozen_string_literal: true

require "json"
require_relative "../prompt_runner"
require_relative "../runner_config"
require_relative "../output_tags"
require_relative "../tools/custom/catalog"
require_relative "../tools/skills/config"
require_relative "../tools_builder/runtime_filtered_catalog"
require_relative "tool_dispatcher"
require_relative "tool_transforms"
require_relative "tool_call_transforms"
require_relative "tool_result_transforms"
require_relative "tool_output_limiter"
require_relative "policies/skills_allowed_tools_policy"

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolLoopRunner
        DEFAULT_MAX_TURNS = 12
        DEFAULT_FIX_EMPTY_FINAL_USER_TEXT = "Please provide your final answer.".freeze
        FINAL_STREAM_SYSTEM_SUFFIX =
          "Tools are now disabled. Using the tool results above, provide your final answer only. Do not request tool calls.".freeze

        class ToolUseError < StandardError
          attr_reader :code, :details

          def initialize(code, message, details: nil)
            super(message)
            @code = code.to_s
            @details = details
          end
        end

        def self.build(client:, runner_config:, tool_executor:, **kwargs)
          prompt_runner = TavernKit::VibeTavern::PromptRunner.new(client: client)

          new(
            prompt_runner: prompt_runner,
            runner_config: runner_config,
            tool_executor: tool_executor,
            **kwargs,
          )
        end

        def initialize(
          prompt_runner:,
          runner_config:,
          tool_executor:,
          variables_store: nil,
          registry: nil,
          system: nil,
          strict: false
        )
          raise ArgumentError, "prompt_runner is required" unless prompt_runner.is_a?(TavernKit::VibeTavern::PromptRunner)
          raise ArgumentError, "runner_config is required" unless runner_config.is_a?(TavernKit::VibeTavern::RunnerConfig)

          @prompt_runner = prompt_runner
          @runner_config = runner_config
          @model = runner_config.model.to_s
          @tool_executor = tool_executor
          @variables_store = variables_store

          # Tool surface assembly (allow/deny masking, surface limits, snapshot)
          # is owned by `TavernKit::VibeTavern::ToolsBuilder`.
          @registry_base = registry || TavernKit::VibeTavern::Tools::Custom::Catalog.new
          @skills_config = TavernKit::VibeTavern::Tools::Skills::Config.from_context(runner_config.context)

          available_tool_names = extract_tool_names(@registry_base.openai_tools(expose: :model))
          @skills_allowed_tools_policy =
            Policies::SkillsAllowedToolsPolicy.new(
              mode: @skills_config.allowed_tools_enforcement,
              invalid_allowlist_mode: @skills_config.allowed_tools_invalid_allowlist,
              available_tool_names: available_tool_names,
              baseline_tool_names: baseline_skills_tool_names,
            )

          @registry =
            TavernKit::VibeTavern::ToolsBuilder::RuntimeFilteredCatalog.new(
              base: @registry_base,
              allow_set_fn: -> { @skills_allowed_tools_policy.allow_set },
            )

          @system = system.to_s
          @strict = strict == true

          cfg = runner_config.tool_calling

          @tool_use_mode = cfg.tool_use_mode
          @tool_failure_policy = cfg.tool_failure_policy
          @tool_calling_fallback_retry_count = cfg.fallback_retry_count
          @fix_empty_final = cfg.fix_empty_final
          @fix_empty_final_user_text = cfg.fix_empty_final_user_text
          @fix_empty_final_disable_tools = cfg.fix_empty_final_disable_tools
          @max_tool_args_bytes = cfg.max_tool_args_bytes
          @max_tool_output_bytes = cfg.max_tool_output_bytes
          @max_tool_calls_per_turn = cfg.max_tool_calls_per_turn
          @tool_choice = cfg.tool_choice
          @request_overrides = cfg.request_overrides
          @message_transforms = cfg.message_transforms
          @tool_transforms = cfg.tool_transforms
          @response_transforms = cfg.response_transforms
          @tool_call_transforms = cfg.tool_call_transforms
          @tool_result_transforms = cfg.tool_result_transforms

          if cfg.tool_use_enabled? && @tool_executor.nil?
            raise ArgumentError, "tool_executor is required when tool_use_mode is enabled"
          end

          @dispatcher =
            if @tool_executor
              ToolDispatcher.new(executor: @tool_executor, registry: @registry, expose: :model)
            end
        end

        def run(user_text:, history: nil, max_turns: DEFAULT_MAX_TURNS, on_event: nil, final_stream: false, &block)
          raise ArgumentError, "model is required" if @model.strip.empty?

          event_handler = on_event.respond_to?(:call) ? on_event : nil
          event_handler ||= block

          history = Array(history).dup
          history = history.map { |m| normalize_history_message(m) }

          trace = []
          pending_user_text = user_text.to_s
          tools_enabled = tool_use_enabled?
          empty_final_fixup_attempted = false
          any_tool_calls_seen = false
          any_tool_success_seen = false
          last_tool_ok_by_name = {}

          max_turns.times do |turn|
            variables_store = @variables_store
            system = @system
            strict = @strict
            tools = @registry.openai_tools(expose: :model)
            tool_choice = @tool_choice || "auto"
            request_overrides = @request_overrides
            message_transforms = @message_transforms
            tool_transforms = @tool_transforms
            response_transforms = @response_transforms
            tool_call_transforms = @tool_call_transforms
            tool_result_transforms = @tool_result_transforms
            request_attempts_left = @tool_use_mode == :relaxed ? @tool_calling_fallback_retry_count : 0

            if pending_user_text && !pending_user_text.strip.empty?
              history << TavernKit::PromptBuilder::Message.new(role: :user, content: pending_user_text.to_s)
              pending_user_text = nil
            end

            tools = ToolTransforms.apply(tools, tool_transforms, strict: @strict) if tools_enabled && tool_transforms.any?

            messages = nil
            options = nil
            request_elapsed_ms = nil
            prompt_request = nil
            prompt_result = nil
            started = nil

            begin
              llm_options_hash = request_overrides
              if tools_enabled
                llm_options_hash = llm_options_hash.merge(tools: tools, tool_choice: tool_choice)
              end

              prompt_request =
                @prompt_runner.build_request(
                  runner_config: @runner_config,
                  history: history,
                  system: system,
                  variables_store: variables_store,
                  strict: strict,
                  llm_options: llm_options_hash,
                  dialect: :openai,
                  message_transforms: message_transforms,
                  response_transforms: response_transforms,
                )

              messages = prompt_request.messages
              options = prompt_request.options

              emit_event(
                event_handler,
                :llm_request_start,
                turn: turn,
                tool_use_mode: @tool_use_mode,
                tool_failure_policy: @tool_failure_policy,
                tools_enabled: tools_enabled,
                messages_count: messages.size,
                tools_count: Array(options.fetch(:tools, [])).size,
                tool_choice: options.fetch(:tool_choice, nil),
                request_attempts_left: request_attempts_left,
              )

              started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              prompt_result = @prompt_runner.perform(prompt_request)
              request_elapsed_ms = prompt_result.elapsed_ms
            rescue SimpleInference::Errors::HTTPError => e
              emit_event(
                event_handler,
                :llm_request_error,
                turn: turn,
                tools_enabled: tools_enabled,
                status: e.status,
                error_class: e.class.name,
                message: e.message.to_s,
              )

              if request_attempts_left > 0
                request_attempts_left -= 1
                tools_enabled = false
                emit_event(
                  event_handler,
                  :llm_request_retry,
                  turn: turn,
                  tools_enabled: tools_enabled,
                  request_attempts_left: request_attempts_left,
                )
                retry
              end

              raise e
            rescue StandardError => e
              elapsed_ms =
                begin
                  if started
                    request_elapsed_ms || ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
                  else
                    nil
                  end
                rescue StandardError
                  nil
                end

              emit_event(
                event_handler,
                :llm_request_error,
                turn: turn,
                tools_enabled: tools_enabled,
                status: e.respond_to?(:status) ? e.status : nil,
                error_class: e.class.name,
                message: e.message.to_s,
                elapsed_ms: elapsed_ms,
              )

              raise e
            end
            body = prompt_result.body
            assistant_msg = prompt_result.assistant_message
            finish_reason = prompt_result.finish_reason

            usage = body.fetch("usage", nil)
            usage = nil unless usage.is_a?(Hash)

            assistant_content = assistant_msg.fetch("content", "").to_s
            tool_calls = normalize_tool_calls_payload(assistant_msg.fetch("tool_calls", nil))
            tool_calls = normalize_tool_calls(tool_calls)
            tool_calls = normalize_tool_call_ids(tool_calls)

            if tools_enabled && tool_call_transforms.any?
              tool_calls = ToolCallTransforms.apply(tool_calls, tool_call_transforms, strict: @strict)
              tool_calls = normalize_tool_calls(tool_calls)
              tool_calls = normalize_tool_call_ids(tool_calls)
            end
            ignored_tool_calls = 0

            if tools_enabled
              max_tool_calls_per_turn = @max_tool_calls_per_turn
              if max_tool_calls_per_turn.nil? && options.fetch(:parallel_tool_calls, nil) == false
                max_tool_calls_per_turn = 1
              end

              if max_tool_calls_per_turn && tool_calls.size > max_tool_calls_per_turn
                ignored_tool_calls = tool_calls.size - max_tool_calls_per_turn
                tool_calls = tool_calls.first(max_tool_calls_per_turn)
              end
            else
              ignored_tool_calls = tool_calls.size
              tool_calls = []
            end

            any_tool_calls_seen ||= tool_calls.any?

            tool_calls_summary =
              tool_calls.map do |tc|
                fn = tc.fetch(:function, {})
                fn = {} unless fn.is_a?(Hash)
                {
                  id: tc.fetch(:id, "").to_s,
                  name: fn.fetch(:name, "").to_s,
                  arguments_bytes: fn.fetch(:arguments, "").to_s.bytesize,
                }
              end

            emit_event(
              event_handler,
              :llm_request_end,
              turn: turn,
              tool_use_mode: @tool_use_mode,
              tool_failure_policy: @tool_failure_policy,
              tools_enabled: tools_enabled,
              elapsed_ms: request_elapsed_ms,
              finish_reason: finish_reason,
              assistant_content_bytes: assistant_content.bytesize,
              usage: usage,
              tool_calls_count: tool_calls.size,
              ignored_tool_calls_count: ignored_tool_calls,
              tool_calls: tool_calls_summary,
            )

            trace_entry = {
              turn: turn,
              request: {
                model: @model,
                messages_count: messages.size,
                tools_count: Array(options.fetch(:tools, [])).size,
                tool_use_mode: @tool_use_mode.to_s,
                tool_failure_policy: @tool_failure_policy.to_s,
                tool_transforms: tool_transforms,
                message_transforms: message_transforms,
                response_transforms: response_transforms,
                tool_call_transforms: tool_call_transforms,
                tool_result_transforms: tool_result_transforms,
              },
              response_summary: {
                has_tool_calls: !tool_calls.empty?,
                tool_calls_count: tool_calls.size,
                ignored_tool_calls_count: ignored_tool_calls,
                usage: usage,
                finish_reason: finish_reason,
              },
              tool_calls: tool_calls_summary,
            }

            trace_entry[:skills_allowed_tools] = skills_allowed_tools_trace_section

            content_stripped = false
            content_sample = nil
            assistant_content_for_history = assistant_content
            if tool_calls.any?
              content_stripped = !assistant_content_for_history.strip.empty?
              content_sample = assistant_content_for_history[0, 200] if content_stripped
              assistant_content_for_history = ""
            end

            if content_stripped
              trace_entry[:response_summary][:assistant_content_stripped] = true
              trace_entry[:response_summary][:assistant_content_sample] = content_sample
            end

            history << TavernKit::PromptBuilder::Message.new(
              role: :assistant,
              content: assistant_content_for_history,
              metadata: tool_calls.empty? ? nil : { tool_calls: tool_calls },
            )

            if tool_calls.empty?
              trace << trace_entry

              if @fix_empty_final &&
                  !empty_final_fixup_attempted &&
                  tool_use_enabled? &&
                  assistant_content.strip.empty? &&
                  any_tool_calls_seen
                empty_final_fixup_attempted = true
                pending_user_text = @fix_empty_final_user_text.to_s.strip
                pending_user_text = DEFAULT_FIX_EMPTY_FINAL_USER_TEXT if pending_user_text.empty?
                disable_tools = @fix_empty_final_disable_tools
                tools_enabled = false if disable_tools

                emit_event(
                  event_handler,
                  :fix_empty_final,
                  turn: turn,
                  disable_tools: disable_tools,
                  user_text_bytes: pending_user_text.to_s.bytesize,
                )
                next
              end

              if @tool_use_mode == :enforced
                unless any_tool_calls_seen
                  raise ToolUseError.new(
                    "NO_TOOL_CALLS",
                    "Tool use is enforced but the assistant requested no tool calls",
                    details: { trace: trace, history: history },
                  )
                end

                case @tool_failure_policy
                when :fatal
                  failed_tools = last_tool_ok_by_name.select { |_name, ok| ok == false }.keys.sort
                  if failed_tools.any?
                    raise ToolUseError.new(
                      "TOOL_ERROR",
                      "Tool use is enforced but at least one tool call failed: #{failed_tools.join(", ")}",
                      details: {
                        failed_tools: failed_tools,
                        tool_failure_policy: @tool_failure_policy.to_s,
                        trace: trace,
                        history: history,
                      },
                    )
                  end
                when :tolerated
                  unless any_tool_success_seen
                    raise ToolUseError.new(
                      "TOOL_ERROR",
                      "Tool use is enforced but no tool call succeeded (tool_failure_policy=tolerated)",
                      details: { tool_failure_policy: @tool_failure_policy.to_s, trace: trace, history: history },
                    )
                  end
                else
                  raise ToolUseError.new(
                    "TOOL_ERROR",
                    "Unknown tool_failure_policy: #{@tool_failure_policy.inspect}",
                    details: { tool_failure_policy: @tool_failure_policy.to_s, trace: trace, history: history },
                  )
                end
              end

              emit_event(
                event_handler,
                :final,
                turn: turn,
                assistant_content_bytes: assistant_content.bytesize,
                any_tool_calls_seen: any_tool_calls_seen,
                any_tool_success_seen: any_tool_success_seen,
              )

              assistant_text =
                TavernKit::VibeTavern::OutputTags.transform(
                  assistant_content,
                  config: @runner_config.output_tags,
                )

              if history.last.is_a?(TavernKit::PromptBuilder::Message)
                history[-1] = history.last.with(content: assistant_text)
              end

              if final_stream == true && any_tool_calls_seen
                non_stream_final_msg = history.pop
                unless non_stream_final_msg.is_a?(TavernKit::PromptBuilder::Message)
                  history << non_stream_final_msg if non_stream_final_msg
                  non_stream_final_msg = nil
                end

                system_stream =
                  [
                    system.to_s,
                    FINAL_STREAM_SYSTEM_SUFFIX,
                  ].map(&:to_s).map(&:strip).reject(&:empty?).join("\n\n")

                emit_event(
                  event_handler,
                  :final_stream_start,
                  turn: turn,
                  messages_count: history.size,
                )

                begin
                  stream_request =
                    @prompt_runner.build_request(
                      runner_config: @runner_config,
                      history: history,
                      system: system_stream,
                      variables_store: variables_store,
                      strict: strict,
                      llm_options: request_overrides,
                      dialect: :openai,
                      message_transforms: [],
                      response_transforms: [],
                    )

                  stream_result =
                    @prompt_runner.perform_stream(stream_request) do |delta|
                      emit_event(
                        event_handler,
                        :final_stream_delta,
                        turn: turn,
                        delta: delta,
                      )
                    end

                  stream_content = stream_result.assistant_message.fetch("content", nil).to_s
                  streamed_text =
                    TavernKit::VibeTavern::OutputTags.transform(
                      stream_content,
                      config: @runner_config.output_tags,
                    )

                  if non_stream_final_msg.is_a?(TavernKit::PromptBuilder::Message)
                    history << non_stream_final_msg.with(content: streamed_text)
                  else
                    history << TavernKit::PromptBuilder::Message.new(role: :assistant, content: streamed_text)
                  end

                  usage = stream_result.body.fetch("usage", nil)
                  usage = nil unless usage.is_a?(Hash)

                  emit_event(
                    event_handler,
                    :final_stream_end,
                    turn: turn,
                    elapsed_ms: stream_result.elapsed_ms,
                    finish_reason: stream_result.finish_reason,
                    assistant_content_bytes: stream_content.bytesize,
                    usage: usage,
                  )

                  trace_entry[:final_stream] = {
                    ok: true,
                    elapsed_ms: stream_result.elapsed_ms,
                    finish_reason: stream_result.finish_reason,
                    usage: usage,
                    assistant_content_bytes: stream_content.bytesize,
                    skipped_reason: nil,
                  }

                  return { assistant_text: streamed_text, history: history, trace: trace }
                rescue ArgumentError => e
                  history << non_stream_final_msg if non_stream_final_msg.is_a?(TavernKit::PromptBuilder::Message)

                  emit_event(
                    event_handler,
                    :final_stream_skipped,
                    turn: turn,
                    message: e.message.to_s,
                  )

                  trace_entry[:final_stream] = {
                    ok: false,
                    elapsed_ms: nil,
                    finish_reason: nil,
                    usage: nil,
                    assistant_content_bytes: nil,
                    skipped_reason: e.message.to_s,
                  }
                rescue StandardError => e
                  history << non_stream_final_msg if non_stream_final_msg.is_a?(TavernKit::PromptBuilder::Message)

                  emit_event(
                    event_handler,
                    :final_stream_error,
                    turn: turn,
                    error_class: e.class.name,
                    message: e.message.to_s,
                  )

                  trace_entry[:final_stream] = {
                    ok: false,
                    elapsed_ms: nil,
                    finish_reason: nil,
                    usage: nil,
                    assistant_content_bytes: nil,
                    skipped_reason: "#{e.class}: #{e.message}",
                  }
                end
              end

              return { assistant_text: assistant_text, history: history, trace: trace }
            end

            tool_results = []
            tool_calls.each do |tc|
              id = tc.fetch(:id, "").to_s.strip
              fn = tc.fetch(:function, {})
              fn = {} unless fn.is_a?(Hash)
              name = fn.fetch(:name, "").to_s.strip
              args_json = fn.fetch(:arguments, nil)

              started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              arguments_bytes =
                case args_json
                when String
                  args_json.bytesize
                when Hash, Array
                  begin
                    JSON.generate(args_json).bytesize
                  rescue StandardError
                    args_json.to_s.bytesize
                  end
                else
                  args_json.to_s.bytesize
                end

              args = parse_args(args_json)
              parse_status = args.is_a?(Hash) ? :ok : args
              emit_event(
                event_handler,
                :tool_call_start,
                turn: turn,
                tool_call_id: id,
                name: name,
                arguments_bytes: arguments_bytes,
                parse_status: parse_status,
              )
              result =
                case args
                when :invalid_json
                  tool_error_envelope(
                    name,
                    code: "ARGUMENTS_JSON_PARSE_ERROR",
                    message: "Invalid JSON in tool call arguments. Retry with arguments as a JSON object only.",
                  )
                when :too_large
                  tool_error_envelope(
                    name,
                    code: "ARGUMENTS_TOO_LARGE",
                    message: "Tool call arguments are too large. Retry with smaller arguments (avoid long strings and unnecessary fields).",
                    data: { bytes: arguments_bytes, max_bytes: @max_tool_args_bytes },
                  )
                else
                  @dispatcher.execute(name: name, args: args, tool_call_id: id)
                end

              effective_tool_name = result.is_a?(Hash) ? result.fetch(:tool_name, name).to_s : name

              if tool_result_transforms.any?
                result =
                  ToolResultTransforms.apply(
                    result,
                    tool_result_transforms,
                    tool_name: effective_tool_name,
                    tool_call_id: id,
                    strict: @strict,
                  )
              end

              output_replaced = false
              limiter = ToolOutputLimiter.check(result, max_bytes: @max_tool_output_bytes)
              unless limiter[:ok]
                output_replaced = true
                result =
                  tool_error_envelope(
                    effective_tool_name,
                    code: "TOOL_OUTPUT_TOO_LARGE",
                    message: "Tool output exceeded size limit",
                    data: {
                      estimated_bytes: limiter[:estimated_bytes],
                      max_bytes: @max_tool_output_bytes,
                      reason: limiter[:reason],
                    },
                  )

                if tool_result_transforms.any?
                  result =
                    ToolResultTransforms.apply(
                      result,
                      tool_result_transforms,
                      tool_name: effective_tool_name,
                      tool_call_id: id,
                      strict: @strict,
                    )
                end
              end

              tool_content =
                begin
                  JSON.generate(result)
                rescue StandardError => e
                  output_replaced = true
                  result =
                    tool_error_envelope(
                      effective_tool_name,
                      code: "TOOL_OUTPUT_SERIALIZATION_ERROR",
                      message: "Tool output could not be serialized to JSON",
                      data: { error_class: e.class.name, message: e.message.to_s },
                    )

                  if tool_result_transforms.any?
                    result =
                      ToolResultTransforms.apply(
                        result,
                        tool_result_transforms,
                        tool_name: effective_tool_name,
                        tool_call_id: id,
                        strict: @strict,
                      )
                  end

                  JSON.generate(result)
                end

              if tool_content.bytesize > @max_tool_output_bytes
                output_replaced = true
                too_large_bytes = tool_content.bytesize
                result =
                  tool_error_envelope(
                    effective_tool_name,
                    code: "TOOL_OUTPUT_TOO_LARGE",
                    message: "Tool output exceeded size limit",
                    data: { bytes: too_large_bytes, max_bytes: @max_tool_output_bytes },
                  )

                if tool_result_transforms.any?
                  result =
                    ToolResultTransforms.apply(
                      result,
                      tool_result_transforms,
                      tool_name: effective_tool_name,
                      tool_call_id: id,
                      strict: @strict,
                    )
                end

                tool_content = JSON.generate(result)
              end

              if maybe_apply_skills_allowed_tools_policy(result, turn: turn, tool_call_id: id, handler: event_handler)
                begin
                  updated = JSON.generate(result)

                  if updated.bytesize <= @max_tool_output_bytes
                    tool_content = updated
                  end
                rescue StandardError
                  nil
                end

                trace_entry[:skills_allowed_tools] = skills_allowed_tools_trace_section
              end

              effective_tool_name = result.is_a?(Hash) ? result.fetch(:tool_name, effective_tool_name).to_s : effective_tool_name

              tool_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
              ok_value = result.is_a?(Hash) ? result[:ok] : nil
              error_codes =
                if result.is_a?(Hash) && result[:errors].is_a?(Array)
                  result[:errors].filter_map { |e| e.is_a?(Hash) ? e[:code] : nil }
                else
                  []
                end

              if error_codes.include?("TOOL_NOT_ALLOWED") && tool_blocked_by_allowed_tools?(effective_tool_name)
                emit_event(
                  event_handler,
                  :tool_call_blocked,
                  turn: turn,
                  tool_call_id: id,
                  name: effective_tool_name,
                  skill_name: @skills_allowed_tools_policy.active_skill_name,
                )
              end

              last_tool_ok_by_name[effective_tool_name] = ok_value
              any_tool_success_seen ||= (ok_value == true)

              emit_event(
                event_handler,
                :tool_call_end,
                turn: turn,
                tool_call_id: id,
                name: effective_tool_name,
                ok: ok_value,
                elapsed_ms: tool_elapsed_ms,
                output_bytes: tool_content.bytesize,
                output_replaced: output_replaced,
                error_codes: error_codes,
              )

              tool_results << {
                id: id,
                name: effective_tool_name,
                ok: ok_value,
                error_codes: error_codes,
              }

              history << TavernKit::PromptBuilder::Message.new(
                role: :tool,
                content: tool_content,
                metadata: id.empty? ? nil : { tool_call_id: id },
              )
            end

            trace_entry[:tool_results] = tool_results
            trace << trace_entry

            pending_user_text = nil # continue after tool results
            tools_enabled = tool_use_enabled?
          end

          raise "Tool loop exceeded max turns (#{max_turns})"
        end

        private

        def normalize_history_message(message)
          return message if message.is_a?(TavernKit::PromptBuilder::Message)

          if message.is_a?(Hash)
            message = TavernKit::Utils.deep_symbolize_keys(message)

            role = message.fetch(:role, "user").to_s
            role = "user" if role.strip.empty?

            content = message.fetch(:content, "").to_s
            metadata = message.fetch(:metadata, nil)

            return TavernKit::PromptBuilder::Message.new(role: role.to_sym, content: content, metadata: metadata)
          end

          if message.respond_to?(:role) && message.respond_to?(:content)
            return TavernKit::PromptBuilder::Message.new(role: message.role.to_sym, content: message.content.to_s, metadata: message.respond_to?(:metadata) ? message.metadata : nil)
          end

          TavernKit::PromptBuilder::Message.new(role: :user, content: message.to_s)
        end

        def emit_event(handler, type, **data)
          return unless handler

          handler.call({ type: type }.merge(data))
        rescue StandardError
          nil
        end

        def tool_use_enabled?
          @tool_use_mode != :disabled
        end

        def parse_args(value)
          return {} if value.nil?

          if value.is_a?(Hash) || value.is_a?(Array)
            normalized = TavernKit::Utils.deep_stringify_keys(value)

            begin
              json = JSON.generate(normalized)
            rescue StandardError
              return :invalid_json
            end

            return :too_large if json.bytesize > @max_tool_args_bytes

            return normalized if normalized.is_a?(Hash)

            return :invalid_json
          end

          str = normalize_argument_string(value.to_s)
          return {} if str.empty?

          return :too_large if str.bytesize > @max_tool_args_bytes

          parsed = JSON.parse(str)

          if parsed.is_a?(String)
            inner = parsed.strip
            return :too_large if inner.bytesize > @max_tool_args_bytes

            begin
              parsed2 = JSON.parse(inner)
              parsed = parsed2 unless parsed2.nil?
            rescue JSON::ParserError
              return :invalid_json
            end
          end

          return TavernKit::Utils.deep_stringify_keys(parsed) if parsed.is_a?(Hash)

          :invalid_json
        rescue JSON::ParserError
          :invalid_json
        end

        def normalize_argument_string(value)
          str = value.to_s.strip
          return str if str.empty?

          fenced = str.match(/\A```(?:json)?\s*(.*?)\s*```\z/mi)
          return str unless fenced

          fenced[1].to_s.strip
        end

        def tool_error_envelope(name, code:, message:, data: nil)
          {
            ok: false,
            tool_name: name,
            data: data.is_a?(Hash) ? data : {},
            warnings: [],
            errors: [
              { code: code, message: message.to_s },
            ],
          }
        end

        def baseline_skills_tool_names
          @baseline_skills_tool_names ||= %w[skills_list skills_load skills_read_file].freeze
        end

        def skills_allowed_tools_trace_section
          allow_set = @skills_allowed_tools_policy.allow_set
          change = @skills_allowed_tools_policy.last_change_details
          change = {} unless change.is_a?(Hash)

          {
            mode: @skills_allowed_tools_policy.mode.to_s,
            invalid_allowlist_mode: @skills_allowed_tools_policy.invalid_allowlist_mode.to_s,
            enforced: !allow_set.nil?,
            skill_name: @skills_allowed_tools_policy.active_skill_name,
            allow_set_count: allow_set ? allow_set.size : 0,
            allow_set_sample: allow_set ? allow_set.keys.first(20) : [],
            ignored_reason: change.fetch(:ignored_reason, nil),
          }
        rescue StandardError
          { mode: "unknown", enforced: false }
        end

        def maybe_apply_skills_allowed_tools_policy(result, turn:, tool_call_id:, handler:)
          return false unless @skills_allowed_tools_policy.mode == :enforce
          return false unless result.is_a?(Hash)
          return false unless result.fetch(:tool_name, nil).to_s == "skills_load"
          return false unless result.fetch(:ok, false) == true

          data = result.fetch(:data, {})
          data = {} unless data.is_a?(Hash)

          skill_name = data.fetch(:name, "").to_s
          allowed_tools = data.fetch(:allowed_tools, nil)
          allowed_tools_raw = data.fetch(:allowed_tools_raw, nil)

          allowed_tools_list =
            case allowed_tools
            when String
              allowed_tools.split(/\s+/)
            else
              Array(allowed_tools)
            end
          allowed_tools_list = allowed_tools_list.map { |v| v.to_s.strip }.reject(&:empty?)

          begin
            @skills_allowed_tools_policy.activate!(
              skill_name: skill_name,
              allowed_tools: allowed_tools_list,
              allowed_tools_raw: allowed_tools_raw,
            )
          rescue ArgumentError => e
            raise ToolUseError.new(
              "ALLOWED_TOOLS_POLICY_ERROR",
              e.message.to_s,
              details: {
                turn: turn,
                tool_call_id: tool_call_id,
                skill_name: skill_name,
                allowed_tools: allowed_tools_list,
                allowed_tools_raw: allowed_tools_raw,
              },
            )
          end

          change = @skills_allowed_tools_policy.last_change_details
          return false unless change.is_a?(Hash)

          emit_event(
            handler,
            :skills_allowed_tools_policy_changed,
            turn: turn,
            skill_name: skill_name,
            allowed_tools_count: allowed_tools_list.size,
            allow_set_count: change.fetch(:allow_set_count, 0),
            mode: @skills_allowed_tools_policy.mode.to_s,
            invalid_allowlist_mode: @skills_allowed_tools_policy.invalid_allowlist_mode.to_s,
            enforced: change.fetch(:enforced, false),
            ignored_reason: change.fetch(:ignored_reason, nil),
            allow_set_sample: change.fetch(:allow_set_sample, []),
          )

          warning = build_allowed_tools_warning(change)
          if warning
            warnings = result.fetch(:warnings, [])
            warnings = [] unless warnings.is_a?(Array)
            warnings = warnings.dup
            warnings << warning
            result[:warnings] = warnings
          end

          true
        end

        def build_allowed_tools_warning(change)
          return nil unless change.is_a?(Hash)

          if change.fetch(:enforced, false) == true
            { code: "ALLOWED_TOOLS_ENFORCED", message: "allowed-tools policy is enforced for the active skill" }
          elsif change.fetch(:ignored_reason, nil).to_s == "NO_MATCHES"
            { code: "ALLOWED_TOOLS_IGNORED", message: "allowed-tools policy ignored: NO_MATCHES" }
          else
            nil
          end
        rescue StandardError
          nil
        end

        def tool_blocked_by_allowed_tools?(tool_name)
          return false unless @skills_allowed_tools_policy.active?

          name = tool_name.to_s
          base_allowed = @registry_base.include?(name, expose: :model)
          runtime_allowed = @registry.include?(name, expose: :model)

          if !base_allowed && name.include?(".")
            underscored = name.tr(".", "_")
            base_allowed = @registry_base.include?(underscored, expose: :model)
            runtime_allowed = @registry.include?(underscored, expose: :model)
          end

          base_allowed && !runtime_allowed
        rescue StandardError
          false
        end

        def extract_tool_names(tools)
          Array(tools).filter_map do |tool|
            next unless tool.is_a?(Hash)

            fn = tool.fetch(:function, nil)
            fn = tool.fetch("function", nil) unless fn.is_a?(Hash)
            next unless fn.is_a?(Hash)

            name = fn.fetch(:name, fn.fetch("name", nil)).to_s.strip
            next if name.empty?

            name
          end
        end

        def normalize_tool_calls_payload(value)
          case value
          when Array
            value.filter_map { |tc| tc.is_a?(Hash) ? TavernKit::Utils.deep_symbolize_keys(tc) : nil }
          when Hash
            [TavernKit::Utils.deep_symbolize_keys(value)]
          else
            []
          end
        end

        # Some models / providers occasionally emit duplicate or empty tool call IDs.
        # Since we resend the assistant message back to the provider on the next turn,
        # we can normalize IDs locally as long as we keep assistant.tool_calls[] and
        # subsequent tool results consistent.
        def normalize_tool_calls(tool_calls)
          tool_calls.map do |tool_call|
            normalized = tool_call.dup

            id = normalized.fetch(:id, "").to_s.strip
            normalized[:id] = id

            fn = normalized.fetch(:function, nil)
            fn = fn.dup if fn.is_a?(Hash)
            fn = {} unless fn.is_a?(Hash)

            fn[:name] = fn.fetch(:name, "").to_s.strip
            normalized[:function] = fn

            normalized
          end
        end

        def normalize_tool_call_ids(tool_calls)
          used = {}

          tool_calls.map.with_index do |tool_call, idx|
            normalized = tool_call.dup
            base_id = normalized.fetch(:id, "").to_s.strip
            base_id = "tc_#{idx + 1}" if base_id.empty?

            id = base_id
            if used.key?(id)
              n = 2
              id = "#{base_id}__#{n}"
              while used.key?(id)
                n += 1
                id = "#{base_id}__#{n}"
              end
            end

            used[id] = true
            normalized[:id] = id
            normalized
          end
        end
      end
    end
  end
end
