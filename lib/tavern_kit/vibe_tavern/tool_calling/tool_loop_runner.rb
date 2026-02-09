# frozen_string_literal: true

require "json"
require_relative "../prompt_runner"
require_relative "filtered_tool_registry"
require_relative "tool_transforms"
require_relative "tool_call_transforms"
require_relative "tool_result_transforms"

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolLoopRunner
        DEFAULT_MAX_TURNS = 12
        MAX_TOOL_ARGS_BYTES = 200_000
        MAX_TOOL_OUTPUT_BYTES = 200_000
        TOOL_USE_MODES = %i[enforced relaxed disabled].freeze
        TOOL_FAILURE_POLICIES = %i[fatal tolerated].freeze
        DEFAULT_FIX_EMPTY_FINAL_USER_TEXT = "Please provide your final answer.".freeze

        class ToolUseError < StandardError
          attr_reader :code, :details

          def initialize(code, message, details: nil)
            super(message)
            @code = code.to_s
            @details = details
          end
        end

        def initialize(
          client:,
          model:,
          tool_executor:,
          runtime: nil,
          variables_store: nil,
          registry: nil,
          system: nil,
          strict: false,
          fix_empty_final: nil,
          tool_use_mode: nil,
          tool_failure_policy: nil,
          tool_calling_fallback_retry_count: nil,
          llm_options_defaults: nil
        )
          @client = client
          @model = model.to_s
          @tool_executor = tool_executor
          @runtime = runtime
          @variables_store = variables_store
          @registry = registry || ToolRegistry.new
          @system = system.to_s
          @strict = strict == true
          @prompt_runner =
            TavernKit::VibeTavern::PromptRunner.new(
              client: @client,
              model: @model,
              llm_options_defaults: llm_options_defaults,
            )
          @tool_use_mode = resolve_tool_use_mode(explicit: tool_use_mode)
          @tool_failure_policy = resolve_tool_failure_policy(explicit: tool_failure_policy)
          @tool_calling_fallback_retry_count =
            resolve_tool_calling_fallback_retry_count(explicit: tool_calling_fallback_retry_count, default: 0)
          @fix_empty_final = resolve_bool_setting(:fix_empty_final, explicit: fix_empty_final, default: true)
          @max_tool_args_bytes = resolve_bytes_setting(:max_tool_args_bytes, default: MAX_TOOL_ARGS_BYTES)
          @max_tool_output_bytes = resolve_bytes_setting(:max_tool_output_bytes, default: MAX_TOOL_OUTPUT_BYTES)

          @registry = resolve_registry_mask(@registry)

          if tool_use_enabled? && @tool_executor.nil?
            raise ArgumentError, "tool_executor is required when tool_use_mode is enabled"
          end

          @dispatcher =
            if @tool_executor
              ToolDispatcher.new(executor: @tool_executor, registry: @registry, expose: :model)
            end
        end

        def run(user_text:, history: nil, max_turns: DEFAULT_MAX_TURNS, on_event: nil, &block)
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
            runtime = @runtime
            variables_store = @variables_store
            system = @system
            strict = @strict
            tools = @registry.openai_tools(expose: :model)
            tool_choice = resolve_tool_choice(default: "auto")
            request_overrides = resolve_request_overrides
            message_transforms = resolve_message_transforms
            tool_transforms = resolve_tool_transforms
            response_transforms = resolve_response_transforms
            tool_call_transforms = resolve_tool_call_transforms
            tool_result_transforms = resolve_tool_result_transforms
            request_attempts_left = @tool_use_mode == :relaxed ? @tool_calling_fallback_retry_count : 0

            if pending_user_text && !pending_user_text.strip.empty?
              history << TavernKit::Prompt::Message.new(role: :user, content: pending_user_text.to_s)
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
                  history: history,
                  system: system,
                  runtime: runtime,
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
              max_tool_calls_per_turn = resolve_max_tool_calls_per_turn(default: nil)
              if max_tool_calls_per_turn.nil? && request_overrides[:parallel_tool_calls] == false
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

            history << TavernKit::Prompt::Message.new(
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
                pending_user_text =
                  resolve_fix_empty_final_user_text(default: DEFAULT_FIX_EMPTY_FINAL_USER_TEXT)
                disable_tools = resolve_fix_empty_final_disable_tools(default: true)
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

              return { assistant_text: assistant_content, history: history, trace: trace }
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
                  @dispatcher.execute(name: name, args: args)
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

              tool_content = JSON.generate(result)
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

                tool_content =
                  JSON.generate(
                    result
                  )
              else
                output_replaced = false
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

              history << TavernKit::Prompt::Message.new(
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
          return message if message.is_a?(TavernKit::Prompt::Message)

          if message.is_a?(Hash)
            message = TavernKit::Utils.deep_symbolize_keys(message)

            role = message.fetch(:role, "user").to_s
            role = "user" if role.strip.empty?

            content = message.fetch(:content, "").to_s
            metadata = message.fetch(:metadata, nil)

            return TavernKit::Prompt::Message.new(role: role.to_sym, content: content, metadata: metadata)
          end

          if message.respond_to?(:role) && message.respond_to?(:content)
            return TavernKit::Prompt::Message.new(role: message.role.to_sym, content: message.content.to_s, metadata: message.respond_to?(:metadata) ? message.metadata : nil)
          end

          TavernKit::Prompt::Message.new(role: :user, content: message.to_s)
        end

        def emit_event(handler, type, **data)
          return unless handler

          handler.call({ type: type }.merge(data))
        rescue StandardError
          nil
        end

        def resolve_bool_setting(key, explicit:, default:)
          return explicit == true unless explicit.nil?

          val = runtime_setting_bool(key)
          val.nil? ? default : val
        end

        def resolve_bytes_setting(key, default:)
          val = runtime_setting_value(key)
          return default if val.nil?

          i = Integer(val)
          return default if i <= 0

          i
        rescue ArgumentError, TypeError
          default
        end

        def resolve_max_tool_calls_per_turn(default:)
          val = runtime_setting_value(:max_tool_calls_per_turn)
          return default if val.nil?

          i = Integer(val)
          return default if i <= 0

          i
        rescue ArgumentError, TypeError
          default
        end

        def resolve_tool_choice(default:)
          raw = runtime_setting_value(:tool_choice)

          case raw
          when nil
            default
          when String
            s = raw.strip
            s.empty? ? default : s
          when Symbol
            raw.to_s
          when Hash
            raw
          else
            default
          end
        end

        def resolve_request_overrides
          raw = runtime_setting_value(:request_overrides)
          return {} unless raw.is_a?(Hash)

          raw = TavernKit::Utils.deep_symbolize_keys(raw)

          # Keep ownership clear: these keys are controlled by ToolLoopRunner.
          reserved = %i[model messages tools tool_choice response_format].freeze
          raw.each_with_object({}) do |(k, v), out|
            key = k.to_s.to_sym
            next if reserved.include?(key)

            out[key] = v
          end
        end

        def runtime_setting_value(key)
          return nil unless @runtime&.respond_to?(:[])

          tool_calling = tool_calling_settings
          if tool_calling
            val = tool_calling[key]
            return val unless val.nil?
          end

          runtime_hash = runtime_settings_hash
          if runtime_hash
            val = runtime_hash[key]
            return val unless val.nil?
          end

          val = @runtime[key]
          return val unless val.nil?

          nil
        end

        def tool_calling_settings
          return @tool_calling_settings if defined?(@tool_calling_settings)

          raw =
            if @runtime.is_a?(Hash)
              runtime_settings_hash&.[](:tool_calling)
            else
              @runtime[:tool_calling]
            end

          @tool_calling_settings = raw.is_a?(Hash) ? TavernKit::Utils.deep_symbolize_keys(raw) : nil
        end

        def runtime_settings_hash
          return @runtime_settings_hash if defined?(@runtime_settings_hash)

          @runtime_settings_hash = @runtime.is_a?(Hash) ? TavernKit::Utils.deep_symbolize_keys(@runtime) : nil
        end

        def runtime_setting_bool(key)
          val = runtime_setting_value(key)
          TavernKit::Coerce.bool(val, default: nil)
        end

        def resolve_fix_empty_final_user_text(default:)
          raw = runtime_setting_value(:fix_empty_final_user_text)

          text = raw.to_s.strip
          text.empty? ? default : text
        end

        def resolve_fix_empty_final_disable_tools(default:)
          val = runtime_setting_bool(:fix_empty_final_disable_tools)

          val.nil? ? default : val
        end

        def resolve_message_transforms
          raw = runtime_setting_value(:message_transforms)

          normalize_string_list(raw)
        end

        def resolve_tool_transforms
          raw = runtime_setting_value(:tool_transforms)

          normalize_string_list(raw)
        end

        def resolve_response_transforms
          raw = runtime_setting_value(:response_transforms)

          normalize_string_list(raw)
        end

        def resolve_tool_call_transforms
          raw = runtime_setting_value(:tool_call_transforms)

          normalize_string_list(raw)
        end

        def resolve_tool_result_transforms
          raw = runtime_setting_value(:tool_result_transforms)

          normalize_string_list(raw)
        end

        def normalize_string_list(value)
          case value
          when nil
            []
          when String
            value.split(",").map(&:strip).reject(&:empty?)
          when Array
            value.map { |v| v.to_s.strip }.reject(&:empty?)
          else
            [value.to_s.strip].reject(&:empty?)
          end
        end

        def resolve_tool_use_mode(explicit:)
          mode = normalize_tool_use_mode(explicit)
          return mode if mode

          mode = normalize_tool_use_mode(runtime_setting_value(:tool_use_mode))
          return mode if mode

          :relaxed
        end

        def resolve_tool_failure_policy(explicit:)
          policy = normalize_tool_failure_policy(explicit)
          return policy if policy

          policy = normalize_tool_failure_policy(runtime_setting_value(:tool_failure_policy))
          return policy if policy

          :fatal
        end

        def normalize_tool_failure_policy(value)
          case value
          when nil
            nil
          else
            s = value.to_s.strip.downcase.tr("-", "_")
            policy =
              case s
              when "fatal"
                :fatal
              when "tolerated"
                :tolerated
              else
                nil
              end

            return nil unless policy
            return policy if TOOL_FAILURE_POLICIES.include?(policy)

            nil
          end
        end

        # Tool profiles/masking:
        # - Keep the model-facing tool list small for reliability
        # - Enforce the same subset in the dispatcher (same registry wrapper)
        def resolve_registry_mask(registry)
          allow = runtime_setting_value(:tool_allowlist)

          deny = runtime_setting_value(:tool_denylist)

          return registry if allow.nil? && deny.nil?

          FilteredToolRegistry.new(base: registry, allow: allow, deny: deny)
        end

        def normalize_tool_use_mode(value)
          case value
          when nil
            nil
          else
            s = value.to_s.strip.downcase
            s = s.tr("-", "_")
            mode =
              case s
              when "enforced", "required", "must"
                :enforced
              when "relaxed", "preferred", "optional"
                :relaxed
              when "disabled", "off", "none", "0", "false"
                :disabled
              else
                nil
              end

            return nil unless mode
            return mode if TOOL_USE_MODES.include?(mode)

            nil
          end
        end

        def resolve_tool_calling_fallback_retry_count(explicit:, default:)
          return normalize_non_negative_int(explicit, default: default) unless explicit.nil?

          normalize_non_negative_int(runtime_setting_value(:fallback_retry_count), default: default)
        end

        def normalize_non_negative_int(value, default:)
          return default if value.nil?

          i = Integer(value)
          return default if i < 0

          i
        rescue ArgumentError, TypeError
          default
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
