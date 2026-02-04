# frozen_string_literal: true

require "json"
require_relative "filtered_tool_registry"
require_relative "message_transforms"
require_relative "tool_transforms"
require_relative "response_transforms"
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
          tool_calling_fallback_retry_count: nil
        )
          @client = client
          @model = model.to_s
          @tool_executor = tool_executor
          @runtime = runtime
          @variables_store = variables_store
          @registry = registry || ToolRegistry.new
          @system = system.to_s
          @strict = strict == true
          @tool_use_mode = resolve_tool_use_mode(explicit: tool_use_mode)
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

        def run(user_text:, history: nil, max_turns: DEFAULT_MAX_TURNS)
          raise ArgumentError, "model is required" if @model.strip.empty?

          history = Array(history).dup
          history = history.map { |m| normalize_history_message(m) }

          trace = []
          pending_user_text = user_text.to_s
          tools_enabled = tool_use_enabled?
          empty_final_fixup_attempted = false
          any_tool_calls_seen = false
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

            tools = ToolTransforms.apply(tools, tool_transforms, strict: @strict) if tools_enabled && tool_transforms.any?

            response = nil
            plan = nil
            messages = nil
            options = nil

            begin
              build_history =
                if system.empty?
                  history
                else
                  [TavernKit::Prompt::Message.new(role: :system, content: system)] + history
                end

              plan =
                TavernKit::VibeTavern.build do
                  history build_history
                  runtime runtime if runtime
                  variables_store variables_store if variables_store

                  llm_options_hash = request_overrides
                  if tools_enabled
                    llm_options_hash = llm_options_hash.merge(tools: tools, tool_choice: tool_choice)
                  end
                  llm_options(llm_options_hash) unless llm_options_hash.empty?

                  strict strict
                  message pending_user_text if pending_user_text && !pending_user_text.empty?
                end

              messages = plan.to_messages(dialect: :openai)
              options = plan.llm_options || {}
              request = { model: @model, messages: messages }.merge(options)

              MessageTransforms.apply!(request.fetch(:messages), message_transforms, strict: @strict) if message_transforms.any?

              response = @client.chat_completions(**request)
            rescue SimpleInference::Errors::HTTPError => e
              if request_attempts_left > 0
                request_attempts_left -= 1
                tools_enabled = false
                retry
              end

              raise e
            end
            body = response.body.is_a?(Hash) ? response.body : {}

            assistant_msg = body.dig("choices", 0, "message")
            assistant_msg = {} unless assistant_msg.is_a?(Hash)
            ResponseTransforms.apply!(assistant_msg, response_transforms, strict: @strict) if response_transforms.any?

            assistant_content = assistant_msg.fetch("content", "").to_s
            tool_calls = deep_symbolize_keys(assistant_msg.fetch("tool_calls", nil))
            tool_calls = Array(tool_calls).select { |tc| tc.is_a?(Hash) }
            tool_calls = normalize_tool_call_ids(tool_calls)

            if tools_enabled && tool_call_transforms.any?
              tool_calls = ToolCallTransforms.apply(tool_calls, tool_call_transforms, strict: @strict)
              tool_calls = normalize_tool_call_ids(tool_calls)
            end
            ignored_tool_calls = 0

            unless tools_enabled
              ignored_tool_calls = tool_calls.size
              tool_calls = []
            end

            any_tool_calls_seen ||= tool_calls.any?

            trace_entry = {
              turn: turn,
              request: {
                model: @model,
                messages_count: messages.size,
                tools_count: Array(options.fetch(:tools, [])).size,
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
                finish_reason: body.dig("choices", 0, "finish_reason"),
              },
              tool_calls: tool_calls.map do |tc|
                fn = tc.fetch(:function, {})
                fn = {} unless fn.is_a?(Hash)
                {
                  id: tc.fetch(:id, "").to_s,
                  name: fn.fetch(:name, "").to_s,
                  arguments_bytes: fn.fetch(:arguments, "").to_s.bytesize,
                }
              end,
            }

            history << TavernKit::Prompt::Message.new(
              role: :assistant,
              content: assistant_content,
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
                tools_enabled = false if resolve_fix_empty_final_disable_tools(default: true)
                next
              end

              if @tool_use_mode == :enforced
                unless any_tool_calls_seen
                  raise ToolUseError.new("NO_TOOL_CALLS", "Tool use is enforced but the assistant requested no tool calls")
                end

                failed_tools = last_tool_ok_by_name.select { |_name, ok| ok == false }.keys.sort
                if failed_tools.any?
                  raise ToolUseError.new(
                    "TOOL_ERROR",
                    "Tool use is enforced but at least one tool call failed: #{failed_tools.join(", ")}",
                    details: { failed_tools: failed_tools },
                  )
                end
              end

              return { assistant_text: assistant_content, history: history, trace: trace }
            end

            tool_results = []
            tool_calls.each do |tc|
              id = tc.fetch(:id, "").to_s
              fn = tc.fetch(:function, {})
              fn = {} unless fn.is_a?(Hash)
              name = fn.fetch(:name, "").to_s
              args_json = fn.fetch(:arguments, nil)

              args = parse_args(args_json)
              result =
                case args
                when :invalid_json
                  tool_error_envelope(name, code: "ARGUMENTS_JSON_PARSE_ERROR", message: "Invalid JSON in tool call arguments")
                when :too_large
                  tool_error_envelope(
                    name,
                    code: "ARGUMENTS_TOO_LARGE",
                    message: "Tool call arguments are too large",
                    data: { "max_bytes" => @max_tool_args_bytes },
                  )
                else
                  @dispatcher.execute(name: name, args: args)
                end

              if tool_result_transforms.any?
                result =
                  ToolResultTransforms.apply(
                    result,
                    tool_result_transforms,
                    tool_name: name,
                    tool_call_id: id,
                    strict: @strict,
                  )
              end

              tool_content = JSON.generate(result)
              if tool_content.bytesize > @max_tool_output_bytes
                too_large_bytes = tool_content.bytesize
                result =
                  tool_error_envelope(
                    name,
                    code: "TOOL_OUTPUT_TOO_LARGE",
                    message: "Tool output exceeded size limit",
                    data: { "bytes" => too_large_bytes, "max_bytes" => @max_tool_output_bytes },
                  )

                if tool_result_transforms.any?
                  result =
                    ToolResultTransforms.apply(
                      result,
                      tool_result_transforms,
                      tool_name: name,
                      tool_call_id: id,
                      strict: @strict,
                    )
                end

                tool_content =
                  JSON.generate(
                    result
                  )
              end

              last_tool_ok_by_name[name] = result.is_a?(Hash) ? result["ok"] : nil

              tool_results << {
                id: id,
                name: name,
                ok: result.is_a?(Hash) ? result["ok"] : nil,
                error_codes:
                  if result.is_a?(Hash) && result["errors"].is_a?(Array)
                    result["errors"].filter_map { |e| e.is_a?(Hash) ? e["code"] : nil }
                  else
                    []
                  end,
              }

              history << TavernKit::Prompt::Message.new(
                role: :tool,
                content: tool_content,
                metadata: id.empty? ? nil : { tool_call_id: id },
              )
            end

            trace_entry[:tool_results] = tool_results
            trace << trace_entry

            pending_user_text = "" # continue after tool results
            tools_enabled = tool_use_enabled?
          end

          raise "Tool loop exceeded max turns (#{max_turns})"
        end

        private

        def normalize_history_message(message)
          return message if message.is_a?(TavernKit::Prompt::Message)

          if message.is_a?(Hash)
            message = deep_symbolize_keys(message)

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

        def resolve_bool_setting(key, explicit:, default:)
          return explicit == true unless explicit.nil?

          val = runtime_setting_bool(key)
          return val if val == true || val == false

          default
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

        def resolve_tool_choice(default:)
          raw = runtime_setting_value(:tool_choice)
          raw = runtime_setting_value(:tool_choice_mode) if raw.nil?

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
          raw = runtime_setting_value(:request_options) if raw.nil?
          return {} unless raw.is_a?(Hash)

          raw = deep_symbolize_keys(raw)

          # Keep ownership clear: these keys are controlled by ToolLoopRunner.
          reserved = %i[model messages tools tool_choice].freeze
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
              @runtime[:tool_calling] || @runtime["tool_calling"]
            else
              @runtime[:tool_calling]
            end

          @tool_calling_settings = raw.is_a?(Hash) ? deep_symbolize_keys(raw) : nil
        end

        def runtime_settings_hash
          return @runtime_settings_hash if defined?(@runtime_settings_hash)

          @runtime_settings_hash = @runtime.is_a?(Hash) ? deep_symbolize_keys(@runtime) : nil
        end

        def runtime_setting_bool(key)
          val = runtime_setting_value(key)
          return val if val == true || val == false

          nil
        end

        def resolve_fix_empty_final_user_text(default:)
          raw = runtime_setting_value(:fix_empty_final_user_text)
          raw = runtime_setting_value(:empty_final_user_text) if raw.nil?
          raw = runtime_setting_value(:finalization_user_text) if raw.nil?

          text = raw.to_s.strip
          text.empty? ? default : text
        end

        def resolve_fix_empty_final_disable_tools(default:)
          val = runtime_setting_bool(:fix_empty_final_disable_tools)
          val = runtime_setting_bool(:empty_final_disable_tools) if val.nil?
          val = runtime_setting_bool(:finalization_disable_tools) if val.nil?

          val.nil? ? default : val
        end

        def resolve_message_transforms
          raw = runtime_setting_value(:message_transforms)
          raw = runtime_setting_value(:outbound_message_transforms) if raw.nil?

          normalize_string_list(raw)
        end

        def resolve_tool_transforms
          raw = runtime_setting_value(:tool_transforms)
          raw = runtime_setting_value(:outbound_tool_transforms) if raw.nil?

          normalize_string_list(raw)
        end

        def resolve_response_transforms
          raw = runtime_setting_value(:response_transforms)
          raw = runtime_setting_value(:inbound_response_transforms) if raw.nil?

          normalize_string_list(raw)
        end

        def resolve_tool_call_transforms
          raw = runtime_setting_value(:tool_call_transforms)
          raw = runtime_setting_value(:inbound_tool_call_transforms) if raw.nil?

          normalize_string_list(raw)
        end

        def resolve_tool_result_transforms
          raw = runtime_setting_value(:tool_result_transforms)
          raw = runtime_setting_value(:outbound_tool_result_transforms) if raw.nil?
          raw = runtime_setting_value(:tool_output_transforms) if raw.nil?

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

        # Tool profiles/masking:
        # - Keep the model-facing tool list small for reliability
        # - Enforce the same subset in the dispatcher (same registry wrapper)
        def resolve_registry_mask(registry)
          allow = runtime_setting_value(:tool_names)
          allow = runtime_setting_value(:tool_allowlist) if allow.nil?
          allow = runtime_setting_value(:allowed_tools) if allow.nil?

          deny = runtime_setting_value(:tool_denylist)
          deny = runtime_setting_value(:disabled_tools) if deny.nil?

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
          return deep_stringify_keys(value) if value.is_a?(Hash)

          str = value.to_s
          return :too_large if str.bytesize > @max_tool_args_bytes

          parsed = JSON.parse(str)
          return deep_stringify_keys(parsed) if parsed.is_a?(Hash)

          :invalid_json
        rescue JSON::ParserError
          :invalid_json
        end

        def deep_stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              out[k.to_s] = deep_stringify_keys(v)
            end
          when Array
            value.map { |v| deep_stringify_keys(v) }
          else
            value
          end
        end

        def tool_error_envelope(name, code:, message:, data: nil)
          {
            "ok" => false,
            "tool_name" => name,
            "data" => data.is_a?(Hash) ? data : {},
            "warnings" => [],
            "errors" => [
              { "code" => code, "message" => message.to_s },
            ],
          }
        end

        def deep_symbolize_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              if k.is_a?(Symbol)
                out[k] = deep_symbolize_keys(v)
              else
                sym = k.to_s.to_sym
                out[sym] = deep_symbolize_keys(v) unless out.key?(sym)
              end
            end
          when Array
            value.map { |v| deep_symbolize_keys(v) }
          else
            value
          end
        end

        # Some models / providers occasionally emit duplicate or empty tool call IDs.
        # Since we resend the assistant message back to the provider on the next turn,
        # we can normalize IDs locally as long as we keep assistant.tool_calls[] and
        # subsequent tool results consistent.
        def normalize_tool_call_ids(tool_calls)
          used = {}

          tool_calls.map.with_index do |tool_call, idx|
            normalized = tool_call.dup
            base_id = normalized.fetch(:id, "").to_s
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
