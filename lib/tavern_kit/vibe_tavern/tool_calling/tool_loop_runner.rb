# frozen_string_literal: true

require "json"

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolLoopRunner
        DEFAULT_MAX_TURNS = 12

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

            trace << {
              turn: turn,
              request: { model: @model, messages_count: messages.size, tools_count: Array(options[:tools] || options["tools"]).size },
              response_summary: {
                has_tool_calls: tool_calls.is_a?(Array) && !tool_calls.empty?,
                finish_reason: body.dig("choices", 0, "finish_reason"),
              },
            }

            history << TavernKit::Prompt::Message.new(
              role: :assistant,
              content: assistant_content,
              metadata: tool_calls ? { tool_calls: tool_calls } : nil,
            )

            tool_calls = Array(tool_calls).select { |tc| tc.is_a?(Hash) }
            return { assistant_text: assistant_content, history: history, trace: trace } if tool_calls.empty?

            tool_calls.each do |tc|
              id = tc["id"].to_s
              fn = tc["function"].is_a?(Hash) ? tc["function"] : {}
              name = fn["name"].to_s
              args_json = fn["arguments"]

              args = parse_args(args_json)
              result =
                if args.nil?
                  {
                    "ok" => false,
                    "tool_name" => name,
                    "data" => {},
                    "warnings" => [],
                    "errors" => [
                      { "code" => "ARGUMENTS_JSON_PARSE_ERROR", "message" => "Invalid JSON in tool call arguments" },
                    ],
                  }
                else
                  dispatcher.execute(name: name, args: args)
                end

              history << TavernKit::Prompt::Message.new(
                role: :tool,
                content: JSON.generate(result),
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

          JSON.parse(value.to_s)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
