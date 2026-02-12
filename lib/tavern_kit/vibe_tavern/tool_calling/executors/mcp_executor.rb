# frozen_string_literal: true

require "json"

require_relative "../../tools/mcp/constants"
require_relative "../tool_output_limiter"
require_relative "../support/envelope"
require_relative "../support/utf8"

module TavernKit
  module VibeTavern
    module ToolCalling
      module Executors
        class McpExecutor
          def initialize(clients:, mapping:, max_bytes: Tools::MCP::DEFAULT_MAX_BYTES)
            @clients = clients.is_a?(Hash) ? clients : {}
            @mapping = mapping.is_a?(Hash) ? mapping : {}

            @max_bytes = Integer(max_bytes)
            raise ArgumentError, "max_bytes must be positive" if @max_bytes <= 0
          end

          def call(name:, args:, tool_call_id: nil)
            local_name = name.to_s
            args = args.is_a?(Hash) ? args : {}

            entry = @mapping.fetch(local_name, nil)
            entry = @mapping.fetch(local_name.to_sym, nil) if entry.nil?
            entry = {} unless entry.is_a?(Hash)

            server_id = entry.fetch(:server_id, entry.fetch("server_id", nil)).to_s
            remote_tool_name = entry.fetch(:remote_tool_name, entry.fetch("remote_tool_name", nil)).to_s

            if server_id.strip.empty? || remote_tool_name.strip.empty?
              return error_envelope(local_name, code: "MCP_TOOL_NOT_FOUND", message: "Unknown MCP tool: #{local_name}")
            end

            client = @clients.fetch(server_id, nil)
            return error_envelope(local_name, code: "MCP_SERVER_NOT_FOUND", message: "Unknown MCP server: #{server_id}") unless client

            result = client.call_tool(name: remote_tool_name, arguments: args)
            result = {} unless result.is_a?(Hash)

            content = result.fetch("content", [])
            content = [] unless content.is_a?(Array)

            structured = result.fetch("structuredContent", nil)
            is_error = result.fetch("isError", false) == true

            text = build_text(content, structured)

            envelope = {
              ok: !is_error,
              tool_name: local_name,
              data: {
                mcp: {
                  server_id: server_id,
                  remote_tool_name: remote_tool_name,
                  content: content,
                  structured_content: structured,
                },
                text: text,
              },
              warnings: [],
              errors: is_error ? [{ code: "MCP_TOOL_ERROR", message: "MCP tool returned isError=true" }] : [],
            }

            enforce_size_limit(envelope)
          rescue ArgumentError => e
            error_envelope(local_name, code: "ARGUMENT_ERROR", message: e.message)
          rescue StandardError => e
            error_envelope(local_name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
          end

          private

          def enforce_size_limit(envelope)
            limiter = ToolCalling::ToolOutputLimiter.check(envelope, max_bytes: @max_bytes)
            return envelope if limiter.fetch(:ok)

            reduced = envelope.dup
            reduced[:warnings] = Array(reduced[:warnings]) + [{ code: "CONTENT_TRUNCATED", message: "MCP tool output was truncated to fit size limit" }]

            reduced_data = reduced.fetch(:data, {}).dup
            reduced_mcp = reduced_data.fetch(:mcp, {}).dup

            reduced_mcp[:content] = summarize_content(reduced_mcp.fetch(:content, []))
            reduced_mcp[:structured_content] = nil

            reduced_data[:mcp] = reduced_mcp
            reduced[:data] = reduced_data

            limiter2 = ToolCalling::ToolOutputLimiter.check(reduced, max_bytes: @max_bytes)
            return reduced if limiter2.fetch(:ok)

            reduced_mcp[:content] = []
            reduced_data[:mcp] = reduced_mcp
            reduced_text = reduced_data.fetch(:text, "").to_s
            truncated_text = truncate_utf8_bytes(reduced_text, max_bytes: @max_bytes / 2)
            truncated_text = normalize_utf8(truncated_text)
            reduced_data[:text] = truncated_text
            reduced[:data] = reduced_data

            if truncated_text.bytesize < reduced_text.bytesize
              reduced[:warnings] = Array(reduced[:warnings]) + [{ code: "TEXT_TRUNCATED", message: "MCP tool text output was truncated to fit size limit" }]
            end

            limiter3 = ToolCalling::ToolOutputLimiter.check(reduced, max_bytes: @max_bytes)
            return reduced if limiter3.fetch(:ok)

            reduced_data[:text] = ""
            reduced[:data] = reduced_data
            reduced[:warnings] = Array(reduced[:warnings]) + [{ code: "TEXT_DROPPED", message: "MCP tool text output was dropped to fit size limit" }]

            reduced
          rescue StandardError
            envelope
          end

          def build_text(content, structured)
            parts = []

            Array(content).each do |block|
              next unless block.is_a?(Hash)

              type = block.fetch("type", "").to_s
              case type
              when "text"
                parts << block.fetch("text", "").to_s
              when "image", "audio"
                mime = block.fetch("mimeType", "").to_s
                bytes = block.fetch("data", "").to_s.bytesize
                parts << "[#{type}: #{mime}, #{bytes} bytes]"
              when "resource_link", "resource"
                uri = block.fetch("uri", block.fetch("url", "")).to_s
                label = uri.strip.empty? ? "" : " #{uri}"
                parts << "[#{type}#{label}]"
              else
                parts << "[content: type=#{type}]"
              end
            end

            if structured
              json =
                begin
                  JSON.generate(structured)
                rescue StandardError
                  structured.to_s
                end
              parts << ""
              parts << "structuredContent:"
              parts << json
            end

            normalize_utf8(parts.join("\n").strip)
          end

          def summarize_content(content)
            Array(content).filter_map do |block|
              next unless block.is_a?(Hash)

              type = block.fetch("type", "").to_s
              case type
              when "text"
                { "type" => "text", "text" => block.fetch("text", "").to_s }
              when "image", "audio"
                data = block.fetch("data", "").to_s
                {
                  "type" => type,
                  "mimeType" => block.fetch("mimeType", nil),
                  "bytes" => data.bytesize,
                }.compact
              when "resource_link", "resource"
                {
                  "type" => type,
                  "uri" => block.fetch("uri", block.fetch("url", nil)),
                  "name" => block.fetch("name", nil),
                }.compact
              else
                { "type" => type }
              end
            end
          end

          def error_envelope(tool_name, code:, message:)
            ToolCalling::Support::Envelope.error_envelope(tool_name, code: code, message: message)
          end

          def truncate_utf8_bytes(value, max_bytes:)
            ToolCalling::Support::Utf8.truncate_utf8_bytes(value, max_bytes: max_bytes)
          end

          def normalize_utf8(value)
            ToolCalling::Support::Utf8.normalize_utf8(value)
          end
        end
      end
    end
  end
end
