# frozen_string_literal: true

require_relative "test_helper"

require "rbconfig"

require_relative "support/fake_streamable_http_server"

class MCPProtocolVersionCompatTest < Minitest::Test
  def test_client_start_raises_when_stdio_server_returns_unsupported_protocol_version
    fixture = File.expand_path("../fixtures/mcp_fake_server.rb", __dir__)

    transport =
      TavernKit::VibeTavern::Tools::MCP::Transport::Stdio.new(
        command: RbConfig.ruby,
        args: [fixture],
        env: { "MCP_FAKE_RETURN_PROTOCOL_VERSION" => "2099-01-01" },
      )

    client =
      TavernKit::VibeTavern::Tools::MCP::Client.new(
        transport: transport,
        protocol_version: "2025-11-25",
        client_info: { "name" => "test", "version" => "0" },
        capabilities: {},
        timeout_s: 1.0,
      )

    assert_raises(TavernKit::VibeTavern::Tools::MCP::Errors::ProtocolVersionNotSupportedError) do
      client.start
    end
  ensure
    client&.close
  end

  def test_client_start_raises_when_streamable_http_server_returns_unsupported_protocol_version
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :json, returned_protocol_version: "2099-01-01")

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
        timeout_s: 2.0,
      )

    assert_raises(TavernKit::VibeTavern::Tools::MCP::Errors::ProtocolVersionNotSupportedError) do
      client.start
    end
  ensure
    client&.close
    server&.close
  end
end
