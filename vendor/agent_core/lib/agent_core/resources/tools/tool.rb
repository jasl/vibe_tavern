# frozen_string_literal: true

module AgentCore
  module Resources
    module Tools
      # A native tool that can be called by the agent.
      #
      # Tools are the fundamental primitives the agent uses to interact with
      # the world. Following pi-mono's philosophy: provide minimal core tools,
      # compose for complex behavior.
      #
      # @example Defining a tool
      #   read_tool = AgentCore::Resources::Tools::Tool.new(
      #     name: "read",
      #     description: "Read the contents of a file",
      #     parameters: {
      #       type: "object",
      #       properties: {
      #         path: { type: "string", description: "File path to read" }
      #       },
      #       required: ["path"]
      #     }
      #   ) do |arguments, context:|
      #     content = File.read(arguments[:path])
      #     AgentCore::Resources::Tools::ToolResult.success(text: content)
      #   end
      class Tool
        attr_reader :name, :description, :parameters, :metadata

        # @param name [String] Unique tool name
        # @param description [String] Description for the LLM
        # @param parameters [Hash] JSON Schema for tool arguments
        # @param metadata [Hash] Optional metadata (category, version, etc.)
        # @param handler [Proc] Block called when tool is invoked
        def initialize(name:, description:, parameters: {}, metadata: {}, &handler)
          @name = name.to_s.freeze
          @description = description.to_s.freeze
          @parameters = (parameters || {}).freeze
          @metadata = (metadata || {}).freeze
          @handler = handler
        end

        # Execute the tool with the given arguments.
        #
        # @param arguments [Hash] Tool arguments (from LLM)
        # @param context [Hash] Execution context (user info, session, etc.)
        # @return [ToolResult]
        def call(arguments, context: {})
          raise AgentCore::Error, "No handler defined for tool '#{name}'" unless @handler
          @handler.call(arguments, context: context)
        rescue AgentCore::Error
          raise
        rescue => e
          ToolResult.error(text: "Tool '#{name}' failed: #{e.message}")
        end

        # Convert to the format expected by LLM APIs.
        # @return [Hash]
        def to_definition
          {
            name: name,
            description: description,
            parameters: parameters,
          }
        end

        # Anthropic-style tool definition.
        def to_anthropic
          {
            name: name,
            description: description,
            input_schema: parameters,
          }
        end

        # OpenAI-style tool definition.
        def to_openai
          {
            type: "function",
            function: {
              name: name,
              description: description,
              parameters: parameters,
            },
          }
        end
      end
    end
  end
end
