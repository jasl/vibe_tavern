# frozen_string_literal: true

require_relative "test_helper"

require_relative "support/fake_streamable_http_server"

class MCPStreamableHttpClientTest < Minitest::Test
  def build_client(server:, sleep_fn: nil, max_response_bytes: nil, headers_provider: nil)
    sleep_fn ||= ->(_seconds) { nil }

    transport =
      TavernKit::VibeTavern::Tools::MCP::Transport::StreamableHttp.new(
        url: server.url,
        headers: {},
        headers_provider: headers_provider,
        timeout_s: 10.0,
        open_timeout_s: 2.0,
        read_timeout_s: 10.0,
        sse_max_reconnects: 5,
        max_response_bytes: max_response_bytes,
        sleep_fn: sleep_fn,
      )

    TavernKit::VibeTavern::Tools::MCP::Client.new(
      transport: transport,
      protocol_version: "2025-11-25",
      client_info: { "name" => "test", "version" => "0" },
      capabilities: {},
      timeout_s: 10.0,
    )
  end

  def test_json_response_handshake_list_tools_and_call_tool
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :json)
    client = build_client(server: server)

    client.start

    page = client.list_tools
    assert_equal 1, Array(page.fetch("tools")).size

    result = client.call_tool(name: "echo", arguments: { "text" => "hi" })
    assert_equal false, result.fetch("isError")
    assert_equal "echo: hi", result.fetch("content").first.fetch("text")
  ensure
    client&.close
    server&.close
  end

  def test_sse_response_single_post
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :sse_single_post)
    client = build_client(server: server)

    client.start
    result = client.call_tool(name: "echo", arguments: { "text" => "hi" })
    assert_equal false, result.fetch("isError")
    assert_equal "echo: hi", result.fetch("content").first.fetch("text")
  ensure
    client&.close
    server&.close
  end

  def test_sse_resume_via_get_last_event_id
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :sse_resume_via_get)
    client = build_client(server: server)

    client.start
    result = client.call_tool(name: "echo", arguments: { "text" => "hi" })
    assert_equal false, result.fetch("isError")
    assert_equal "echo: hi", result.fetch("content").first.fetch("text")

    ids = server.last_event_id_requests
    assert ids.any? { |s| !s.to_s.strip.empty? }
  ensure
    client&.close
    server&.close
  end

  def test_retry_field_controls_reconnect_delay
    sleeps = []
    sleep_fn = ->(seconds) { sleeps << seconds }

    server = McpFakeStreamableHttpServer.new(tools_call_mode: :sse_resume_via_get, retry_ms: 123)
    client = build_client(server: server, sleep_fn: sleep_fn)

    client.start
    client.call_tool(name: "echo", arguments: { "text" => "hi" })

    assert_in_delta 0.123, sleeps.first.to_f, 0.001
  ensure
    client&.close
    server&.close
  end

  def test_session_404_triggers_reinitialize_and_retries_tools_list_once
    server =
      McpFakeStreamableHttpServer.new(
        tools_call_mode: :json,
        invalidate_session_after_first_tools_list: true,
      )
    client = build_client(server: server)

    client.start

    page1 = client.list_tools
    assert_equal 1, Array(page1.fetch("tools")).size

    page2 = client.list_tools
    assert_equal 1, Array(page2.fetch("tools")).size

    assert_equal 2, server.initialize_count
    assert_equal 2, server.tools_list_count
    assert_equal 1, server.not_found_count
  ensure
    client&.close
    server&.close
  end

  def test_session_404_triggers_reinitialize_but_does_not_retry_tools_call
    server =
      McpFakeStreamableHttpServer.new(
        tools_call_mode: :json,
        invalidate_session_after_first_tools_list: true,
      )
    client = build_client(server: server)

    client.start
    client.list_tools

    err =
      assert_raises(TavernKit::VibeTavern::Tools::MCP::JsonRpcError) do
        client.call_tool(name: "echo", arguments: { "text" => "hi" })
      end
    assert_equal "MCP_SESSION_NOT_FOUND", err.code

    assert_equal 2, server.initialize_count
    assert_equal 1, server.tools_list_count
    assert_equal 0, server.tools_call_count
    assert_equal 1, server.not_found_count
  ensure
    client&.close
    server&.close
  end

  def test_timeout_sends_cancel_notification_best_effort
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :json, tools_call_delay_s: 0.25)

    transport =
      TavernKit::VibeTavern::Tools::MCP::Transport::StreamableHttp.new(
        url: server.url,
        headers: {},
        timeout_s: 1.0,
        open_timeout_s: 1.0,
        read_timeout_s: 1.0,
        sse_max_reconnects: 5,
        sleep_fn: ->(_seconds) { nil },
      )

    client =
      TavernKit::VibeTavern::Tools::MCP::Client.new(
        transport: transport,
        protocol_version: "2025-11-25",
        client_info: { "name" => "test", "version" => "0" },
        capabilities: {},
        timeout_s: 0.05,
      )

    client.start

    assert_raises(TavernKit::VibeTavern::Tools::MCP::Errors::TimeoutError) do
      client.call_tool(name: "echo", arguments: { "text" => "hi" })
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
    until server.cancelled_requests.any? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end

    assert server.cancelled_requests.any?
    params = server.cancelled_requests.first
    assert_equal 2, params.fetch("requestId")
    assert_equal "timeout", params.fetch("reason")
  ensure
    client&.close
    server&.close
  end

  def test_json_body_too_large_returns_http_body_too_large
    server =
      McpFakeStreamableHttpServer.new(
        tools_call_mode: :json,
        tools_call_result_text_bytes: 5000,
      )

    client = build_client(server: server, max_response_bytes: 1000)

    client.start

    err =
      assert_raises(TavernKit::VibeTavern::Tools::MCP::JsonRpcError) do
        client.call_tool(name: "echo", arguments: { "text" => "hi" })
      end
    assert_equal "HTTP_BODY_TOO_LARGE", err.code
  ensure
    client&.close
    server&.close
  end

  def test_sse_event_data_too_large_returns_sse_event_data_too_large
    server =
      McpFakeStreamableHttpServer.new(
        tools_call_mode: :sse_single_post,
        tools_call_result_text_bytes: 5000,
      )

    client = build_client(server: server, max_response_bytes: 1000)

    client.start

    err =
      assert_raises(TavernKit::VibeTavern::Tools::MCP::JsonRpcError) do
        client.call_tool(name: "echo", arguments: { "text" => "hi" })
      end
    assert_equal "SSE_EVENT_DATA_TOO_LARGE", err.code
  ensure
    client&.close
    server&.close
  end

  def test_sse_invalid_json_returns_invalid_sse_event_data
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :sse_invalid_json)
    client = build_client(server: server)

    client.start

    err =
      assert_raises(TavernKit::VibeTavern::Tools::MCP::JsonRpcError) do
        client.call_tool(name: "echo", arguments: { "text" => "hi" })
      end
    assert_equal "INVALID_SSE_EVENT_DATA", err.code
  ensure
    client&.close
    server&.close
  end

  def test_headers_provider_is_included_in_initialize_and_requests
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :json)

    token = "Bearer test"
    provider = -> { { "Authorization" => token } }

    client = build_client(server: server, headers_provider: provider)

    client.start
    client.list_tools

    seen = server.authorization_headers.compact
    assert_operator seen.size, :>=, 2
    assert seen.all? { |value| value == token }
  ensure
    client&.close
    server&.close
  end

  def test_headers_provider_errors_raise_transport_error
    server = McpFakeStreamableHttpServer.new(tools_call_mode: :json)
    provider = -> { raise "boom" }

    client = build_client(server: server, headers_provider: provider)

    assert_raises(TavernKit::VibeTavern::Tools::MCP::Errors::TransportError) do
      client.start
    end
  ensure
    client&.close
    server&.close
  end
end
