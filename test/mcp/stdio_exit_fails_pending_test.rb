# frozen_string_literal: true

require_relative "test_helper"

require "rbconfig"

class MCPStdioExitFailsPendingTest < Minitest::Test
  def test_pending_requests_fail_fast_when_stdio_process_exits
    fixture = File.expand_path("../fixtures/mcp_fake_server.rb", __dir__)

    transport =
      TavernKit::VibeTavern::Tools::MCP::Transport::Stdio.new(
        command: RbConfig.ruby,
        args: [fixture],
        env: { "MCP_FAKE_EXIT_ON_TOOLS_LIST" => "1" },
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

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(TavernKit::VibeTavern::Tools::MCP::Errors::TransportError) do
      client.list_tools(timeout_s: 5.0)
    end
    elapsed_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert_operator elapsed_s, :<, 1.0
  ensure
    client&.close
  end
end
