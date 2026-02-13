# frozen_string_literal: true

require_relative "test_helper"

require_relative "support/fake_streamable_http_server"

class MCPPerRequestTimeoutTest < Minitest::Test
  def test_call_tool_honors_per_request_timeout_override
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :json, tools_call_delay_s: 0.25)

    transport =
      TavernKit::VibeTavern::Tools::MCP::Transport::StreamableHttp.new(
        url: server.url,
        headers: {},
        timeout_s: 2.0,
        open_timeout_s: 1.0,
        read_timeout_s: 2.0,
        sse_max_reconnects: 2,
        sleep_fn: ->(_seconds) { nil },
      )

    client =
      TavernKit::VibeTavern::Tools::MCP::Client.new(
        transport: transport,
        protocol_version: "2025-11-25",
        client_info: { "name" => "test", "version" => "0" },
        capabilities: {},
        timeout_s: 1.0,
      )

    client.start

    ok = client.call_tool(name: "echo", arguments: { "text" => "hi" })
    assert_equal false, ok.fetch("isError")

    assert_raises(TavernKit::VibeTavern::Tools::MCP::Errors::TimeoutError) do
      client.call_tool(name: "echo", arguments: { "text" => "hi" }, timeout_s: 0.05)
    end
  ensure
    client&.close
    server&.close
  end
end
