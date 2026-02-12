# frozen_string_literal: true

require_relative "constants"

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
          ) do
            def initialize(
              id:,
              command:,
              args: nil,
              env: nil,
              chdir: nil,
              protocol_version: nil,
              client_info: nil,
              capabilities: nil,
              timeout_s: nil
            )
              id = id.to_s.strip
              raise ArgumentError, "id is required" if id.empty?

              command = command.to_s.strip
              raise ArgumentError, "command is required" if command.empty?

              protocol_version = normalize_protocol_version(protocol_version)
              timeout_s = normalize_timeout_s(timeout_s)

              super(
                id: id,
                command: command,
                args: Array(args).map(&:to_s),
                env: normalize_env(env),
                chdir: blank?(chdir) ? nil : chdir.to_s,
                protocol_version: protocol_version,
                client_info: client_info.is_a?(Hash) ? client_info : nil,
                capabilities: capabilities.is_a?(Hash) ? capabilities : {},
                timeout_s: timeout_s,
              )
            end

            def self.coerce(value)
              return value if value.is_a?(MCP::ServerConfig)

              unless value.is_a?(Hash)
                raise ArgumentError, "server config must be an MCP::ServerConfig or Hash"
              end

              TavernKit::Utils.assert_symbol_keys!(value, path: "mcp server config")

              new(
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

            private

            def blank?(value)
              value.nil? || value.to_s.strip.empty?
            end

            def normalize_env(value)
              if !value.nil? && !value.is_a?(Hash)
                raise ArgumentError, "env must be a Hash"
              end

              hash = value || {}

              hash.each_with_object({}) do |(k, v), out|
                key = k.to_s
                next if key.strip.empty?

                out[key] = v.nil? ? nil : v.to_s
              end
            end

            def normalize_protocol_version(value)
              s = value.to_s.strip
              s.empty? ? MCP::DEFAULT_PROTOCOL_VERSION : s
            end

            def normalize_timeout_s(value)
              timeout_s = Float(value.nil? ? MCP::DEFAULT_TIMEOUT_S : value)
              raise ArgumentError, "timeout_s must be positive" if timeout_s <= 0

              timeout_s
            end
          end
      end
    end
  end
end
