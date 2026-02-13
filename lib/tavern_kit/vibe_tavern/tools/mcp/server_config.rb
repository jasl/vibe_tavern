# frozen_string_literal: true

require_relative "constants"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        ServerConfig =
          Data.define(
            :id,
            :transport,
            :command,
            :args,
            :env,
            :chdir,
            :url,
            :headers,
            :protocol_version,
            :client_info,
            :capabilities,
            :timeout_s,
            :open_timeout_s,
            :read_timeout_s,
            :sse_max_reconnects,
            :max_response_bytes,
          ) do
            def initialize(
              id:,
              transport: nil,
              command: nil,
              args: nil,
              env: nil,
              chdir: nil,
              url: nil,
              headers: nil,
              protocol_version: nil,
              client_info: nil,
              capabilities: nil,
              timeout_s: nil,
              open_timeout_s: nil,
              read_timeout_s: nil,
              sse_max_reconnects: nil,
              max_response_bytes: nil
            )
              id = id.to_s.strip
              raise ArgumentError, "id is required" if id.empty?

              transport = normalize_transport(transport)

              command = blank?(command) ? nil : command.to_s.strip
              url = blank?(url) ? nil : url.to_s.strip

              case transport
              when :stdio
                raise ArgumentError, "command is required" if command.nil? || command.empty?

                if url
                  raise ArgumentError, "url must be empty for stdio transport"
                end

                http_headers = normalize_headers(headers)
                if !http_headers.nil? && !http_headers.empty?
                  raise ArgumentError, "headers must be empty for stdio transport"
                end

                if !open_timeout_s.nil?
                  raise ArgumentError, "open_timeout_s must be empty for stdio transport"
                end

                if !read_timeout_s.nil?
                  raise ArgumentError, "read_timeout_s must be empty for stdio transport"
                end

                if !sse_max_reconnects.nil?
                  raise ArgumentError, "sse_max_reconnects must be empty for stdio transport"
                end

                if !max_response_bytes.nil?
                  raise ArgumentError, "max_response_bytes must be empty for stdio transport"
                end
              when :streamable_http
                raise ArgumentError, "url is required" if url.nil? || url.empty?

                if command
                  raise ArgumentError, "command must be empty for streamable_http transport"
                end

                if !Array(args).empty?
                  raise ArgumentError, "args must be empty for streamable_http transport"
                end

                env_hash = normalize_env(env)
                if !env_hash.empty?
                  raise ArgumentError, "env must be empty for streamable_http transport"
                end

                if !blank?(chdir)
                  raise ArgumentError, "chdir must be empty for streamable_http transport"
                end

                open_timeout_s = normalize_optional_timeout_s(open_timeout_s, field: "open_timeout_s")
                read_timeout_s = normalize_optional_timeout_s(read_timeout_s, field: "read_timeout_s")
                sse_max_reconnects = normalize_optional_positive_integer(sse_max_reconnects, field: "sse_max_reconnects")
                max_response_bytes = normalize_optional_positive_integer(max_response_bytes, field: "max_response_bytes")

                headers = normalize_headers(headers) || {}
                args = []
                env = {}
                chdir = nil
              else
                raise ArgumentError, "unsupported transport: #{transport.inspect}"
              end

              protocol_version = normalize_protocol_version(protocol_version)
              timeout_s = normalize_timeout_s(timeout_s)

              super(
                id: id,
                transport: transport,
                command: command,
                args: Array(args).map(&:to_s),
                env: normalize_env(env),
                chdir: blank?(chdir) ? nil : chdir.to_s,
                url: url,
                headers: headers,
                protocol_version: protocol_version,
                client_info: client_info.is_a?(Hash) ? client_info : nil,
                capabilities: capabilities.is_a?(Hash) ? capabilities : {},
                timeout_s: timeout_s,
                open_timeout_s: open_timeout_s,
                read_timeout_s: read_timeout_s,
                sse_max_reconnects: sse_max_reconnects,
                max_response_bytes: max_response_bytes,
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
                transport: value.fetch(:transport, nil),
                command: value.fetch(:command, nil),
                args: value.fetch(:args, nil),
                env: value.fetch(:env, nil),
                chdir: value.fetch(:chdir, nil),
                url: value.fetch(:url, nil),
                headers: value.fetch(:headers, nil),
                protocol_version: value.fetch(:protocol_version, nil),
                client_info: value.fetch(:client_info, nil),
                capabilities: value.fetch(:capabilities, nil),
                timeout_s: value.fetch(:timeout_s, nil),
                open_timeout_s: value.fetch(:open_timeout_s, nil),
                read_timeout_s: value.fetch(:read_timeout_s, nil),
                sse_max_reconnects: value.fetch(:sse_max_reconnects, nil),
                max_response_bytes: value.fetch(:max_response_bytes, nil),
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

            def normalize_headers(value)
              return nil if value.nil?

              unless value.is_a?(Hash)
                raise ArgumentError, "headers must be a Hash"
              end

              value.each_with_object({}) do |(k, v), out|
                key = k.to_s
                next if key.strip.empty?
                next if v.nil?

                out[key] = v.to_s
              end
            end

            def normalize_transport(value)
              raw = value.to_s.strip
              return :stdio if raw.empty?

              case raw
              when "stdio"
                :stdio
              when "streamable_http", "streamable-http"
                :streamable_http
              else
                raise ArgumentError, "transport must be :stdio or :streamable_http"
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

            def normalize_optional_timeout_s(value, field:)
              return nil if value.nil?

              timeout_s = Float(value)
              raise ArgumentError, "#{field} must be positive" if timeout_s <= 0

              timeout_s
            end

            def normalize_optional_positive_integer(value, field:)
              return nil if value.nil?

              i = Integer(value)
              raise ArgumentError, "#{field} must be positive" if i <= 0

              i
            end
          end
      end
    end
  end
end
