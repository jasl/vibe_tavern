# frozen_string_literal: true

require_relative "../../tools_builder/definition"
require_relative "client"
require_relative "tool_adapter"
require_relative "transport/stdio"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        ServerConfig =
          Data.define(
            :id,
            :command,
            :args,
            :env,
            :chdir,
            :protocol_version,
            :client_info,
            :capabilities,
            :timeout_s,
          )

        class ToolRegistryBuilder
          BuildResult = Data.define(:definitions, :mapping, :clients)

          def initialize(servers:)
            @servers = Array(servers)
          end

          def build
            definitions = []
            mapping = {}
            clients = {}

            @servers.each do |server|
              cfg = coerce_server_config(server)

              server_id = cfg.id.to_s.strip
              raise ArgumentError, "server id is required" if server_id.empty?
              raise ArgumentError, "duplicate server id: #{server_id}" if clients.key?(server_id)

              transport =
                MCP::Transport::Stdio.new(
                  command: cfg.command,
                  args: cfg.args || [],
                  env: cfg.env || {},
                  chdir: cfg.chdir,
                )

              client =
                MCP::Client.new(
                  transport: transport,
                  protocol_version: cfg.protocol_version || MCP::DEFAULT_PROTOCOL_VERSION,
                  client_info: cfg.client_info,
                  capabilities: cfg.capabilities,
                  timeout_s: cfg.timeout_s || MCP::DEFAULT_TIMEOUT_S,
                )

              clients[server_id] = client
              client.start

              cursor = nil
              loop do
                page = client.list_tools(cursor: cursor)
                tools = page.fetch("tools", [])
                tools = [] unless tools.is_a?(Array)

                tools.each do |tool|
                  next unless tool.is_a?(Hash)

                  remote_name = tool.fetch("name", "").to_s
                  next if remote_name.strip.empty?

                  local_name = MCP::ToolAdapter.local_tool_name(server_id: server_id, remote_tool_name: remote_name)
                  entry = MCP::ToolAdapter.mapping_entry(server_id: server_id, remote_tool_name: remote_name)

                  if mapping.key?(local_name) && mapping.fetch(local_name) != entry
                    raise ArgumentError, "MCP tool name collision: #{local_name}"
                  end

                  unless mapping.key?(local_name)
                    remote_description = tool.fetch("description", "").to_s
                    input_schema = tool.fetch("inputSchema", nil)
                    input_schema = { type: "object", properties: {} } unless input_schema.is_a?(Hash)

                    definitions <<
                      ToolsBuilder::Definition.new(
                        name: local_name,
                        description: "#{remote_description} (MCP: #{server_id})".strip,
                        parameters: input_schema,
                      )
                  end

                  mapping[local_name] = entry
                end

                cursor = page.fetch("nextCursor", nil).to_s.strip
                break if cursor.empty?
              end
            end

            definitions.sort_by!(&:name)
            BuildResult.new(definitions: definitions, mapping: mapping, clients: clients)
          rescue StandardError
            clients.each_value do |client|
              begin
                client.close
              rescue StandardError
                nil
              end
            end

            raise
          end

          private

          def coerce_server_config(value)
            return value if value.is_a?(MCP::ServerConfig)

            raise ArgumentError, "server config must be an MCP::ServerConfig" unless value.is_a?(Hash)

            MCP::ServerConfig.new(
              id: value.fetch(:id),
              command: value.fetch(:command),
              args: value.fetch(:args, nil),
              env: value.fetch(:env, nil),
              chdir: value.fetch(:chdir, nil),
              protocol_version: value.fetch(:protocol_version, nil),
              client_info: value.fetch(:client_info, nil),
              capabilities: value.fetch(:capabilities, nil),
              timeout_s: value.fetch(:timeout_s, nil),
            )
          end
        end
      end
    end
  end
end
