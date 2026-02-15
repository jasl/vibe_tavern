# frozen_string_literal: true

module AgentCore
  module Resources
    module Tools
      # Unified registry for all tool sources (native, MCP, skills).
      #
      # The registry is the single point of contact for tool discovery
      # and execution. It delegates to the appropriate source based on
      # tool name.
      #
      # @example Building a registry
      #   registry = AgentCore::Resources::Tools::Registry.new
      #
      #   # Register native tools
      #   registry.register(read_tool)
      #   registry.register(write_tool)
      #
      #   # Register MCP servers (tools discovered during init)
      #   registry.register_mcp_server(mcp_client)
      #
      #   # List all available tools
      #   registry.definitions  # => Array of tool definitions
      #
      #   # Execute a tool
      #   result = registry.execute(name: "read", arguments: { "path" => "config.json" })
      class Registry
        def initialize
          @native_tools = {}
          @mcp_clients = {}
          @mcp_tools = {}   # name => { client:, definition: }
          @mutex = Mutex.new
        end

        # Register a native tool.
        # @param tool [Tool]
        # @return [self]
        def register(tool)
          @mutex.synchronize do
            if @mcp_tools.key?(tool.name)
              warn "[AgentCore::Registry] Native tool '#{tool.name}' shadows existing MCP tool"
            end
            @native_tools[tool.name] = tool
          end
          self
        end

        # Register multiple native tools.
        # @param tools [Array<Tool>]
        # @return [self]
        def register_many(tools)
          tools.each { |tool| register(tool) }
          self
        end

        # Register an MCP client (its tools become available).
        #
        # @param client [MCP::Client] An initialized MCP client
        # @param prefix [String, nil] Optional prefix for tool names (e.g., "mcp_server1_")
        # @return [self]
        def register_mcp_client(client, prefix: nil)
          tools = list_all_mcp_tool_definitions(client)

          @mutex.synchronize do
            @mcp_clients[client.object_id] = client

            tools.each do |tool_def|
              tool_name = prefix ? "#{prefix}#{tool_def[:name]}" : tool_def[:name]
              if @native_tools.key?(tool_name)
                warn "[AgentCore::Registry] MCP tool '#{tool_name}' conflicts with existing native tool (native takes priority)"
              elsif @mcp_tools.key?(tool_name)
                warn "[AgentCore::Registry] MCP tool '#{tool_name}' overwrites previously registered MCP tool"
              end
              @mcp_tools[tool_name] = {
                client: client,
                definition: tool_def,
                original_name: tool_def[:name],
              }
            end
          end
          self
        end

        # Find a tool by name.
        # @param name [String]
        # @return [Tool, Hash, nil] Native Tool or MCP tool info
        def find(name)
          @mutex.synchronize do
            @native_tools[name] || @mcp_tools[name]
          end
        end

        # Whether a tool with the given name exists.
        def include?(name)
          @mutex.synchronize do
            @native_tools.key?(name) || @mcp_tools.key?(name)
          end
        end

        # Execute a tool by name.
        #
        # @param name [String] Tool name
        # @param arguments [Hash] Tool arguments
        # @param context [ExecutionContext, Hash, nil] Execution context
        # @return [ToolResult]
        # @raise [ToolNotFoundError] If tool is not registered
        def execute(name:, arguments:, context: nil)
          execution_context = ExecutionContext.from(context)
          tool_info = @mutex.synchronize { @native_tools[name] || @mcp_tools[name] }

          raise ToolNotFoundError.new("Tool not found: #{name}", tool_name: name) unless tool_info

          case tool_info
          when Tool
            tool_info.call(arguments, context: execution_context)
          when Hash
            # MCP tool — wrap in rescue to normalize errors to ToolResult
            client = tool_info[:client]
            original_name = tool_info[:original_name]
            begin
              mcp_result = client.call_tool(name: original_name, arguments: arguments)
              result_hash = AgentCore::Utils.normalize_mcp_tool_call_result(mcp_result)
              ToolResult.new(
                content: result_hash[:content],
                error: result_hash.fetch(:error, false)
              )
            rescue => e
              ToolResult.error(text: "MCP tool '#{original_name}' failed: #{e.message}")
            end
          end
        end

        # Get all tool definitions (for sending to LLM).
        #
        # @param format [Symbol] :generic, :anthropic, or :openai
        # @return [Array<Hash>]
        def definitions(format: :generic)
          @mutex.synchronize do
            native = @native_tools.values.map { |t| format_definition(t, format) }
            mcp = @mcp_tools.map { |name, info|
              format_mcp_definition(name, info[:definition], format)
            }
            native + mcp
          end
        end

        # All registered tool names.
        # @return [Array<String>]
        def tool_names
          @mutex.synchronize { @native_tools.keys + @mcp_tools.keys }
        end

        # Number of registered tools.
        def size
          @mutex.synchronize { @native_tools.size + @mcp_tools.size }
        end

        # Remove all tools.
        def clear
          @mutex.synchronize do
            @native_tools.clear
            @mcp_clients.clear
            @mcp_tools.clear
          end
          self
        end

        private

        def format_definition(tool, format)
          case format
          when :anthropic then tool.to_anthropic
          when :openai then tool.to_openai
          else tool.to_definition
          end
        end

        def format_mcp_definition(name, definition, format)
          desc = definition.fetch(:description, "").to_s
          params = definition.fetch(:input_schema) { definition.fetch(:parameters, {}) }
          params = {} unless params.is_a?(Hash)

          case format
          when :anthropic
            { name: name, description: desc, input_schema: params }
          when :openai
            { type: "function", function: { name: name, description: desc, parameters: params } }
          else
            { name: name, description: desc, parameters: params }
          end
        end

        def list_all_mcp_tool_definitions(client)
          cursor = nil
          seen = {}
          out = []

          loop do
            page = client.list_tools(cursor: cursor)
            page = {} unless page.is_a?(Hash)

            Array(page.fetch("tools", nil)).each do |tool_def|
              normalized = AgentCore::Utils.normalize_mcp_tool_definition(tool_def)
              out << normalized if normalized
            end

            next_cursor = page.fetch("nextCursor", "").to_s.strip
            break if next_cursor.empty?
            break if seen[next_cursor]

            seen[next_cursor] = true
            cursor = next_cursor
          end

          out
        end
      end
    end
  end
end
