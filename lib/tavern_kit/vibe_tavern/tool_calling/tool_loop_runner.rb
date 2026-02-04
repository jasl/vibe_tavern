# frozen_string_literal: true

require "json"
require_relative "filtered_tool_registry"

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolLoopRunner
        DEFAULT_MAX_TURNS = 12
        MAX_TOOL_ARGS_BYTES = 200_000
        MAX_TOOL_OUTPUT_BYTES = 200_000
        TOOL_USE_MODES = %i[enforced relaxed disabled].freeze

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
          workspace:,
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
          @workspace = workspace
          @runtime = runtime
          @variables_store = variables_store
          @registry = registry || ToolRegistry.new
          @system = system.to_s
          @strict = strict == true
          @tool_use_mode = resolve_tool_use_mode(explicit: tool_use_mode)
          @tool_calling_fallback_retry_count =
            resolve_tool_calling_fallback_retry_count(explicit: tool_calling_fallback_retry_count, default: 0)
          @fix_empty_final = resolve_bool_setting(:fix_empty_final, explicit: fix_empty_final, default: true)

          @registry = resolve_registry_mask(@registry)
        end

        def run(user_text:, history: nil, max_turns: DEFAULT_MAX_TURNS)
          raise ArgumentError, "model is required" if @model.strip.empty?

          history = Array(history).dup
          history = history.map { |m| normalize_history_message(m) }

          dispatcher = ToolDispatcher.new(workspace: @workspace, registry: @registry, expose: :model)

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
            request_attempts_left = @tool_use_mode == :relaxed ? @tool_calling_fallback_retry_count : 0

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

                  if tools_enabled
                    llm_options(
                      tools: tools,
                      tool_choice: "auto",
                    )
                  end

                  strict strict
                  message pending_user_text if pending_user_text && !pending_user_text.empty?
                end

              messages = plan.to_messages(dialect: :openai)
              options = plan.llm_options || {}
              request = { model: @model, messages: messages }.merge(options)

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

            assistant_msg = body.dig("choices", 0, "message") || {}
            assistant_content = assistant_msg["content"].to_s
            tool_calls = assistant_msg["tool_calls"]
            tool_calls = Array(tool_calls).select { |tc| tc.is_a?(Hash) }
            tool_calls = normalize_tool_call_ids(tool_calls)
            ignored_tool_calls = 0

            unless tools_enabled
              ignored_tool_calls = tool_calls.size
              tool_calls = []
            end

            any_tool_calls_seen ||= tool_calls.any?

            trace_entry = {
              turn: turn,
              request: { model: @model, messages_count: messages.size, tools_count: Array(options[:tools] || options["tools"]).size },
              response_summary: {
                has_tool_calls: !tool_calls.empty?,
                tool_calls_count: tool_calls.size,
                ignored_tool_calls_count: ignored_tool_calls,
                finish_reason: body.dig("choices", 0, "finish_reason"),
              },
              tool_calls: tool_calls.map do |tc|
                fn = tc["function"].is_a?(Hash) ? tc["function"] : {}
                {
                  id: tc["id"].to_s,
                  name: fn["name"].to_s,
                  arguments_bytes: fn["arguments"].to_s.bytesize,
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
                  trace.any? { |t| t.is_a?(Hash) && t.dig(:response_summary, :has_tool_calls) == true }
                tools_enabled = false
                empty_final_fixup_attempted = true
                pending_user_text = %(Reply with a single sentence: "Done.")
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
              id = tc["id"].to_s
              fn = tc["function"].is_a?(Hash) ? tc["function"] : {}
              name = fn["name"].to_s
              args_json = fn["arguments"]

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
                    data: { "max_bytes" => MAX_TOOL_ARGS_BYTES },
                  )
                else
                  dispatcher.execute(name: name, args: args)
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

              tool_content = JSON.generate(result)
              if tool_content.bytesize > MAX_TOOL_OUTPUT_BYTES
                tool_content =
                  JSON.generate(
                    tool_error_envelope(
                      name,
                      code: "TOOL_OUTPUT_TOO_LARGE",
                      message: "Tool output exceeded size limit",
                      data: { "bytes" => tool_content.bytesize, "max_bytes" => MAX_TOOL_OUTPUT_BYTES },
                    )
                  )
              end

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
            role = (message[:role] || message["role"]).to_s
            role = role.empty? ? "user" : role
            content = (message[:content] || message["content"]).to_s
            metadata = message[:metadata] || message["metadata"]
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

        def runtime_setting_value(key)
          return nil unless @runtime&.respond_to?(:[])

          # Prefer a dedicated namespace under runtime:
          #   runtime[:tool_calling] => { tool_use_mode: :enforced, fallback_retry_count: 0, fix_empty_final: true }
          tool_calling = @runtime[:tool_calling]
          if tool_calling.is_a?(Hash)
            val = tool_calling[key]
            val = tool_calling[key.to_s] if val.nil?
            return val unless val.nil?
          end

          val = @runtime[key]
          val = @runtime[key.to_s] if val.nil?
          return val unless val.nil?

          nil
        end

        def runtime_setting_bool(key)
          val = runtime_setting_value(key)
          return val if val == true || val == false

          nil
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
          return value if value.is_a?(Hash)

          str = value.to_s
          return :too_large if str.bytesize > MAX_TOOL_ARGS_BYTES

          JSON.parse(str)
        rescue JSON::ParserError
          :invalid_json
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

        # Some models / providers occasionally emit duplicate or empty tool call IDs.
        # Since we resend the assistant message back to the provider on the next turn,
        # we can normalize IDs locally as long as we keep assistant.tool_calls[] and
        # subsequent tool results consistent.
        def normalize_tool_call_ids(tool_calls)
          used = {}

          tool_calls.map.with_index do |tool_call, idx|
            normalized = tool_call.dup
            base_id = normalized["id"].to_s
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
            normalized["id"] = id
            normalized
          end
        end
      end
    end
  end
end
