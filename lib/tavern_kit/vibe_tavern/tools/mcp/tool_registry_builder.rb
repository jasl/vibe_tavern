# frozen_string_literal: true

require_relative "../../tools_builder/definition"
require_relative "constants"
require_relative "client"
require_relative "server_config"
require_relative "snapshot"
require_relative "tool_adapter"
require_relative "transport/stdio"
require_relative "transport/streamable_http"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        class ToolRegistryBuilder
          def initialize(servers:)
            @servers = Array(servers)
          end

          def build
            definitions = []
            mapping = {}
            clients = {}

            @servers.each do |server|
              cfg = ServerConfig.coerce(server)

              server_id = cfg.id.to_s.strip
              raise ArgumentError, "server id is required" if server_id.empty?
              raise ArgumentError, "duplicate server id: #{server_id}" if clients.key?(server_id)

              transport =
                case cfg.transport
                when :stdio
                  env = cfg.env || {}
                  if cfg.env_provider
                    provided_env = cfg.env_provider.call
                    raise ArgumentError, "env_provider must return a Hash" unless provided_env.is_a?(Hash)

                    normalized_env =
                      provided_env.each_with_object({}) do |(k, v), out|
                        key = k.to_s
                        next if key.strip.empty?

                        out[key] = v.nil? ? nil : v.to_s
                      end

                    env = env.merge(normalized_env)
                  end

                  MCP::Transport::Stdio.new(
                    command: cfg.command,
                    args: cfg.args || [],
                    env: env,
                    chdir: cfg.chdir,
                    on_stdout_line: cfg.on_stdout_line,
                    on_stderr_line: cfg.on_stderr_line,
                  )
                when :streamable_http
                  MCP::Transport::StreamableHttp.new(
                    url: cfg.url,
                    headers: cfg.headers,
                    headers_provider: cfg.headers_provider,
                    timeout_s: cfg.timeout_s || MCP::DEFAULT_TIMEOUT_S,
                    open_timeout_s: cfg.open_timeout_s,
                    read_timeout_s: cfg.read_timeout_s,
                    sse_max_reconnects: cfg.sse_max_reconnects,
                    max_response_bytes: cfg.max_response_bytes,
                    on_stdout_line: cfg.on_stdout_line,
                    on_stderr_line: cfg.on_stderr_line,
                  )
                else
                  raise ArgumentError, "unsupported MCP transport: #{cfg.transport.inspect}"
                end

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
            Snapshot.new(definitions: definitions, mapping: mapping, clients: clients)
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
        end
      end
    end
  end
end
