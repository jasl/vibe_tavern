# frozen_string_literal: true

require_relative "constants"
require_relative "errors"
require_relative "json_rpc_client"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        class Client
          attr_reader :protocol_version, :server_info, :server_capabilities, :instructions

          def initialize(
            transport:,
            protocol_version: MCP::DEFAULT_PROTOCOL_VERSION,
            client_info: nil,
            capabilities: nil,
            timeout_s: MCP::DEFAULT_TIMEOUT_S,
            on_notification: nil
          )
            raise ArgumentError, "transport is required" if transport.nil?

            protocol_version = protocol_version.to_s.strip
            protocol_version = MCP::DEFAULT_PROTOCOL_VERSION if protocol_version.empty?

            @transport = transport
            @protocol_version = protocol_version
            @client_info = normalize_hash(client_info) || default_client_info
            @capabilities = normalize_hash(capabilities) || {}
            @timeout_s = Float(timeout_s)
            raise ArgumentError, "timeout_s must be positive" if @timeout_s <= 0

            @on_notification = on_notification.respond_to?(:call) ? on_notification : nil

            @rpc = MCP::JsonRpcClient.new(transport: @transport, timeout_s: @timeout_s, on_notification: @on_notification)

            @server_info = nil
            @server_capabilities = nil
            @instructions = nil
            @started = false
          end

          def start
            return self if @started

            @rpc.start

            initialize_session!

            @started = true
            self
          end

          def list_tools(cursor: nil)
            params = {}
            cursor = cursor.to_s.strip
            params["cursor"] = cursor unless cursor.empty?

            attempt = 0

            begin
              attempt += 1

              result = @rpc.request("tools/list", params.empty? ? {} : params)
              result.is_a?(Hash) ? result : {}
            rescue MCP::JsonRpcError => e
              raise unless e.code.to_s == "MCP_SESSION_NOT_FOUND"
              raise if attempt > 1

              reinitialize_session!
              retry
            end
          end

          def call_tool(name:, arguments: {})
            tool_name = name.to_s
            raise ArgumentError, "name is required" if tool_name.strip.empty?

            args = arguments.is_a?(Hash) ? arguments : {}
            result = @rpc.request("tools/call", { "name" => tool_name, "arguments" => args })
            result.is_a?(Hash) ? result : {}
          rescue MCP::JsonRpcError => e
            if e.code.to_s == "MCP_SESSION_NOT_FOUND"
              begin
                reinitialize_session!
              rescue StandardError
                nil
              end
            end

            raise
          end

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
            { "name" => "vibe_tavern", "version" => TavernKit::VERSION.to_s }
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
            @protocol_version = returned_protocol_version.empty? ? @protocol_version : returned_protocol_version

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
  end
end
