# frozen_string_literal: true

require_relative "test_helper"

require_relative "support/fake_streamable_http_server"

class MCPToolRegistryBuilderStreamableHttpTest < Minitest::Test
  def test_builds_registry_over_streamable_http
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :json)

    cfg =
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "fake",
        transport: :streamable_http,
        url: server.url,
        headers: {},
        protocol_version: "2025-11-25",
        client_info: { "name" => "test", "version" => "0" },
        capabilities: {},
        timeout_s: 5.0,
        open_timeout_s: 2.0,
        read_timeout_s: 5.0,
        sse_max_reconnects: 5,
      )

    snapshot = TavernKit::VibeTavern::Tools::MCP::ToolRegistryBuilder.new(servers: [cfg]).build

    remote_names = snapshot.mapping.values.map { |v| v.fetch(:remote_tool_name) }.sort
    assert_includes remote_names, "echo"
    assert_includes remote_names, "mixed.content"

    client = snapshot.clients.fetch("fake")
    result = client.call_tool(name: "echo", arguments: { "text" => "hi" })

    assert_equal false, result.fetch("isError")
    assert_equal "echo: hi", result.fetch("content").first.fetch("text")
  ensure
    snapshot&.close
    server&.close
  end
end
