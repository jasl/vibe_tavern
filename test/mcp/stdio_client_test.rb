# frozen_string_literal: true

require_relative "test_helper"

require "rbconfig"

class MCPStdioClientTest < Minitest::Test
  def test_handshake_list_tools_and_call_tool
    fixture = File.expand_path("../fixtures/mcp_fake_server.rb", __dir__)

    transport =
      TavernKit::VibeTavern::Tools::MCP::Transport::Stdio.new(
        command: RbConfig.ruby,
        args: [fixture],
      )

    client =
      TavernKit::VibeTavern::Tools::MCP::Client.new(
        transport: transport,
        protocol_version: "2025-11-25",
        client_info: { "name" => "test", "version" => "0" },
        capabilities: {},
        timeout_s: 5.0,
      )

    client.start

    assert client.server_info.is_a?(Hash)
    assert_equal "mcp_fake_server", client.server_info.fetch("name")

    page1 = client.list_tools
    assert_equal 1, Array(page1["tools"]).size
    assert_equal "page2", page1.fetch("nextCursor")

    page2 = client.list_tools(cursor: page1.fetch("nextCursor"))
    assert_equal 1, Array(page2["tools"]).size

    result = client.call_tool(name: "echo", arguments: { "text" => "hi" })
    assert_equal false, result.fetch("isError")
    assert_equal "hi", result.fetch("content").first.fetch("text")
    assert_equal({ "tool" => "echo", "arguments" => { "text" => "hi" } }, result.fetch("structuredContent"))
  ensure
    client&.close
  end
end
