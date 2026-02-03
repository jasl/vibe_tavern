# frozen_string_literal: true

require "json"

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolLoopRunner
        DEFAULT_MAX_TURNS = 12
        MAX_TOOL_ARGS_BYTES = 200_000
        MAX_TOOL_OUTPUT_BYTES = 200_000

        def initialize(client:, model:, workspace:, runtime: nil, variables_store: nil, registry: nil, system: nil, strict: false)
          @client = client
          @model = model.to_s
          @workspace = workspace
          @runtime = runtime
          @variables_store = variables_store
          @registry = registry || ToolRegistry.new
          @system = system.to_s
          @strict = strict == true
        end

        def run(user_text:, history: nil, max_turns: DEFAULT_MAX_TURNS)
          raise ArgumentError, "model is required" if @model.strip.empty?

          history = Array(history).dup
          history = history.map { |m| normalize_history_message(m) }

          dispatcher = ToolDispatcher.new(workspace: @workspace, registry: @registry, expose: :model)

          trace = []
          pending_user_text = user_text.to_s

          max_turns.times do |turn|
            runtime = @runtime
            variables_store = @variables_store
            system = @system
            strict = @strict
            tools = @registry.openai_tools(expose: :model)
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

                llm_options(
                  tools: tools,
                  tool_choice: "auto",
                )

                strict strict
                message pending_user_text if pending_user_text && !pending_user_text.empty?
              end

            messages = plan.to_messages(dialect: :openai)
            options = plan.llm_options || {}

            request = { model: @model, messages: messages }.merge(options)

            response = @client.chat_completions(**request)
            body = response.body.is_a?(Hash) ? response.body : {}

            assistant_msg = body.dig("choices", 0, "message") || {}
            assistant_content = assistant_msg["content"].to_s
            tool_calls = assistant_msg["tool_calls"]
            tool_calls = Array(tool_calls).select { |tc| tc.is_a?(Hash) }
            tool_calls = normalize_tool_call_ids(tool_calls)

            trace << {
              turn: turn,
              request: { model: @model, messages_count: messages.size, tools_count: Array(options[:tools] || options["tools"]).size },
              response_summary: {
                has_tool_calls: !tool_calls.empty?,
                finish_reason: body.dig("choices", 0, "finish_reason"),
              },
            }

            history << TavernKit::Prompt::Message.new(
              role: :assistant,
              content: assistant_content,
              metadata: tool_calls.empty? ? nil : { tool_calls: tool_calls },
            )

            return { assistant_text: assistant_content, history: history, trace: trace } if tool_calls.empty?

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

            pending_user_text = "" # continue after tool results
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
