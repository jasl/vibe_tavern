# frozen_string_literal: true

require "digest"

module AgentCore
  module MCP
    # Maps MCP server + remote tool names to local tool names.
    #
    # Local names use the format: mcp_{server_id}__{tool_name}
    # with sanitized components. Names longer than 128 chars get
    # a SHA256 suffix to ensure uniqueness.
    module ToolAdapter
      module_function

      # Build a local tool name from server ID and remote tool name.
      #
      # @param server_id [String] The MCP server identifier
      # @param remote_tool_name [String] The tool name on the MCP server
      # @return [String] Sanitized local tool name (max 128 chars)
      def local_tool_name(server_id:, remote_tool_name:)
        server = sanitize_component(server_id, fallback: "server")
        tool = sanitize_component(remote_tool_name, fallback: "tool")

        base = "mcp_#{server}__#{tool}"
        return base if base.length <= 128

        suffix = Digest::SHA256.hexdigest(base)[0, 10]
        prefix_len = 128 - 1 - suffix.length
        prefix = base.byteslice(0, prefix_len).to_s

        "#{prefix}_#{suffix}"
      end

      # Build a mapping entry linking local name to server/remote info.
      #
      # @param server_id [String] The MCP server identifier
      # @param remote_tool_name [String] The tool name on the MCP server
      # @return [Hash] { server_id:, remote_tool_name: }
      def mapping_entry(server_id:, remote_tool_name:)
        {
          server_id: server_id.to_s,
          remote_tool_name: remote_tool_name.to_s,
        }
      end

      # Sanitize a name component for use in tool names.
      #
      # @param value [String]
      # @param fallback [String] Default if value is blank
      # @return [String]
      def sanitize_component(value, fallback:)
        raw = value.to_s.strip
        raw = fallback if raw.empty?

        out =
          raw
            .tr(".", "_")
            .gsub(/[^A-Za-z0-9_-]/, "_")

        out = fallback if out.strip.empty?
        out
      end
      private_class_method :sanitize_component
    end
  end
end
