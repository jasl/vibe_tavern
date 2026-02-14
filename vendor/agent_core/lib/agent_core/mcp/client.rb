# frozen_string_literal: true

module AgentCore
  module MCP
    # High-level MCP client.
    #
    # Handles the MCP lifecycle: initialize handshake, protocol version
    # negotiation, and tool operations. Uses JsonRpcClient for the
    # JSON-RPC layer.
    #
    # Auto-reconnects (re-initializes) on MCP_SESSION_NOT_FOUND errors
    # from list_tools and call_tool.
    class Client
      attr_reader :protocol_version, :server_info, :server_capabilities, :instructions

      # @param transport [Transport::Base] The underlying transport
      # @param protocol_version [String] Desired MCP protocol version
      # @param client_info [Hash, nil] Client identification
      # @param capabilities [Hash, nil] Client capabilities
      # @param timeout_s [Float] Default request timeout
      # @param on_notification [#call, nil] Callback for server notifications
      def initialize(
        transport:,
        protocol_version: AgentCore::MCP::DEFAULT_PROTOCOL_VERSION,
        client_info: nil,
        capabilities: nil,
        timeout_s: AgentCore::MCP::DEFAULT_TIMEOUT_S,
        on_notification: nil
      )
        raise ArgumentError, "transport is required" if transport.nil?

        protocol_version = protocol_version.to_s.strip
        protocol_version = AgentCore::MCP::DEFAULT_PROTOCOL_VERSION if protocol_version.empty?

        @transport = transport
        @protocol_version = protocol_version
        @client_info = normalize_hash(client_info) || default_client_info
        @capabilities = normalize_hash(capabilities) || {}
        @timeout_s = Float(timeout_s)
        raise ArgumentError, "timeout_s must be positive" if @timeout_s <= 0

        @on_notification = on_notification.respond_to?(:call) ? on_notification : nil

        @rpc = AgentCore::MCP::JsonRpcClient.new(
          transport: @transport,
          timeout_s: @timeout_s,
          on_notification: @on_notification,
        )

        @server_info = nil
        @server_capabilities = nil
        @instructions = nil
        @started = false
      end

      # Start the client: start transport + negotiate MCP session.
      # @return [self]
      def start
        return self if @started

        @rpc.start
        initialize_session!
        @started = true
        self
      end

      # List available tools from the MCP server.
      #
      # @param cursor [String, nil] Pagination cursor
      # @param timeout_s [Float, nil] Override timeout
      # @return [Hash] The tools/list response (string keys)
      def list_tools(cursor: nil, timeout_s: nil)
        params = {}
        cursor = cursor.to_s.strip
        params["cursor"] = cursor unless cursor.empty?

        attempt = 0

        begin
          attempt += 1
          result = @rpc.request("tools/list", params.empty? ? {} : params, timeout_s: timeout_s)
          result.is_a?(Hash) ? result : {}
        rescue AgentCore::MCP::JsonRpcError => e
          raise unless e.code.to_s == "MCP_SESSION_NOT_FOUND"
          raise if attempt > 1

          reinitialize_session!
          retry
        end
      end

      # Call a tool on the MCP server.
      #
      # @param name [String] Tool name
      # @param arguments [Hash] Tool arguments
      # @param timeout_s [Float, nil] Override timeout
      # @return [Hash] The tools/call response (string keys)
      def call_tool(name:, arguments: {}, timeout_s: nil)
        tool_name = name.to_s
        raise ArgumentError, "name is required" if tool_name.strip.empty?

        args = arguments.is_a?(Hash) ? arguments : {}
        attempt = 0

        begin
          attempt += 1
          result = @rpc.request("tools/call", { "name" => tool_name, "arguments" => args }, timeout_s: timeout_s)
          result.is_a?(Hash) ? result : {}
        rescue AgentCore::MCP::JsonRpcError => e
          raise unless e.code.to_s == "MCP_SESSION_NOT_FOUND"
          raise if attempt > 1

          reinitialize_session!
          retry
        end
      end

      # Close the client.
      # @return [nil]
      def close
        @rpc.close
      end

      private

      def normalize_hash(value)
        return nil if value.nil?
        return value if value.is_a?(Hash)

        nil
      end

      def default_client_info
        { "name" => "agent_core", "version" => AgentCore::VERSION.to_s }
      end

      def initialize_session!
        result =
          @rpc.request(
            "initialize",
            {
              "protocolVersion" => @protocol_version,
              "clientInfo" => @client_info,
              "capabilities" => @capabilities,
            },
          )
        result = {} unless result.is_a?(Hash)

        @server_info = result.fetch("serverInfo", nil)
        @server_capabilities = result.fetch("capabilities", nil)
        @instructions = result.fetch("instructions", nil)

        returned_protocol_version = result.fetch("protocolVersion", nil).to_s.strip
        negotiated_protocol_version = returned_protocol_version.empty? ? @protocol_version : returned_protocol_version
        unless AgentCore::MCP::SUPPORTED_PROTOCOL_VERSIONS.include?(negotiated_protocol_version)
          begin
            @rpc.close
          rescue StandardError
            nil
          end

          raise AgentCore::MCP::ProtocolVersionNotSupportedError,
                "Unsupported MCP protocol version: #{negotiated_protocol_version.inspect} " \
                "(supported: #{AgentCore::MCP::SUPPORTED_PROTOCOL_VERSIONS.join(", ")})"
        end

        @protocol_version = negotiated_protocol_version

        if @transport.respond_to?(:protocol_version=)
          @transport.protocol_version = @protocol_version
        end

        @rpc.notify("notifications/initialized")
      end

      def reinitialize_session!
        initialize_session!
      end
    end
  end
end
