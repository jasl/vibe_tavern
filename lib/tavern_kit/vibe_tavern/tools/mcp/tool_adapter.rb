# frozen_string_literal: true

require "digest"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        module ToolAdapter
          module_function

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

          def mapping_entry(server_id:, remote_tool_name:)
            {
              server_id: server_id.to_s,
              remote_tool_name: remote_tool_name.to_s,
            }
          end

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
  end
end
