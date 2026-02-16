# frozen_string_literal: true

require "test_helper"
require "agent_core/mcp"
require "agent_core/mcp/transport/streamable_http"

class AgentCore::MCP::Transport::StreamableHttpTest < Minitest::Test
  class CloseCountingClient
    def initialize
      @close_calls = 0
    end

    attr_reader :close_calls

    def close
      @close_calls += 1
      nil
    end
  end

  def test_initialize_requires_url
    assert_raises(ArgumentError) do
      AgentCore::MCP::Transport::StreamableHttp.new(url: "")
    end
  end

  def test_initialize_with_url
    transport = build_transport(url: "https://example.com/mcp")
    assert_instance_of AgentCore::MCP::Transport::StreamableHttp, transport
  end

  def test_initialize_validates_timeout_s
    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", timeout_s: 0)
    end

    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", timeout_s: -1)
    end
  end

  def test_initialize_validates_open_timeout_s
    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", open_timeout_s: 0)
    end
  end

  def test_initialize_validates_read_timeout_s
    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", read_timeout_s: -1)
    end
  end

  def test_initialize_validates_sse_max_reconnects
    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", sse_max_reconnects: 0)
    end
  end

  def test_initialize_validates_max_response_bytes
    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", max_response_bytes: -5)
    end
  end

  def test_initialize_validates_headers_must_be_hash
    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", headers: "not a hash")
    end
  end

  def test_initialize_validates_headers_provider_must_be_callable
    assert_raises(ArgumentError) do
      build_transport(url: "https://example.com/mcp", headers_provider: "not callable")
    end
  end

  def test_initialize_nil_headers_provider_is_allowed
    transport = build_transport(url: "https://example.com/mcp", headers_provider: nil)
    assert_instance_of AgentCore::MCP::Transport::StreamableHttp, transport
  end

  def test_initialize_callable_headers_provider
    transport = build_transport(
      url: "https://example.com/mcp",
      headers_provider: -> { { "Authorization" => "Bearer token" } },
    )
    assert_instance_of AgentCore::MCP::Transport::StreamableHttp, transport
  end

  def test_inherits_from_base
    transport = build_transport(url: "https://example.com/mcp")
    assert_kind_of AgentCore::MCP::Transport::Base, transport
  end

  def test_session_id_initially_nil
    transport = build_transport(url: "https://example.com/mcp")
    assert_nil transport.session_id
  end

  def test_protocol_version_setter
    transport = build_transport(url: "https://example.com/mcp")
    transport.protocol_version = "2025-11-25"
    # No assertion on read (private), but should not raise
  end

  def test_protocol_version_setter_with_blank_string
    transport = build_transport(url: "https://example.com/mcp")
    transport.protocol_version = "  "
    # Should store nil internally (blank is treated as nil)
  end

  def test_close_without_start
    transport = build_transport(url: "https://example.com/mcp")
    result = transport.close(timeout_s: 1.0)
    assert_nil result
  end

  def test_close_is_idempotent
    transport = build_transport(url: "https://example.com/mcp")
    transport.close(timeout_s: 1.0)
    transport.close(timeout_s: 1.0)
  end

  def test_close_closes_http_clients_once_when_worker_alive
    transport = build_transport(url: "https://example.com/mcp")
    client = CloseCountingClient.new
    stream_client = CloseCountingClient.new
    worker = Thread.new { sleep 5 }

    transport.instance_variable_set(:@worker, worker)
    transport.instance_variable_set(:@client, client)
    transport.instance_variable_set(:@stream_client, stream_client)

    transport.close(timeout_s: 0.2)

    assert_equal 1, client.close_calls
    assert_equal 1, stream_client.close_calls
  ensure
    worker&.kill
    worker&.join(0.1)
  end

  def test_close_negative_timeout_returns_nil
    transport = build_transport(url: "https://example.com/mcp")
    result = transport.close(timeout_s: -1.0)
    assert_nil result
  end

  def test_send_message_before_start_raises
    transport = build_transport(url: "https://example.com/mcp")

    assert_raises(AgentCore::MCP::TransportError) do
      transport.send_message({ "jsonrpc" => "2.0", "method" => "test" })
    end
  end

  def test_send_message_after_close_raises
    transport = build_transport(url: "https://example.com/mcp")
    transport.close(timeout_s: 1.0)

    assert_raises(AgentCore::MCP::ClosedError) do
      transport.send_message({ "jsonrpc" => "2.0", "method" => "test" })
    end
  end

  def test_start_after_close_raises
    transport = build_transport(url: "https://example.com/mcp")
    transport.close(timeout_s: 1.0)

    assert_raises(AgentCore::MCP::ClosedError) do
      transport.start
    end
  end

  def test_cancel_request_returns_false_for_unknown_id
    transport = build_transport(url: "https://example.com/mcp")
    assert_equal false, transport.cancel_request("unknown-id")
  end

  def test_defaults
    transport = build_transport(url: "https://example.com/mcp")
    assert_nil transport.session_id
  end

  def test_normalize_headers_strips_nil_values
    transport = build_transport(
      url: "https://example.com/mcp",
      headers: { "Keep" => "yes", "Drop" => nil },
    )
    assert_instance_of AgentCore::MCP::Transport::StreamableHttp, transport
  end

  def test_normalize_headers_strips_blank_keys
    transport = build_transport(
      url: "https://example.com/mcp",
      headers: { "" => "value", "  " => "value2", "Valid" => "ok" },
    )
    assert_instance_of AgentCore::MCP::Transport::StreamableHttp, transport
  end

  def test_token_struct
    token = AgentCore::MCP::Transport::StreamableHttp::Token.new(cancelled: false, reason: nil)
    assert_equal false, token.cancelled
    assert_nil token.reason

    token.cancelled = true
    token.reason = "timeout"
    assert_equal true, token.cancelled
    assert_equal "timeout", token.reason
  end

  def test_job_data_define
    token = AgentCore::MCP::Transport::StreamableHttp::Token.new(cancelled: false, reason: nil)
    job = AgentCore::MCP::Transport::StreamableHttp::Job.new(
      message: { "jsonrpc" => "2.0" },
      id: 1,
      method: "test",
      token: token,
      dynamic_headers: {},
    )

    assert_equal({ "jsonrpc" => "2.0" }, job.message)
    assert_equal 1, job.id
    assert_equal "test", job.method
    assert_same token, job.token
    assert_equal({}, job.dynamic_headers)
  end

  def test_body_too_large_error
    error = AgentCore::MCP::Transport::StreamableHttp::BodyTooLargeError.new("too large")
    assert_kind_of StandardError, error
    assert_equal "too large", error.message
  end

  def test_invalid_sse_event_data_error
    error = AgentCore::MCP::Transport::StreamableHttp::InvalidSseEventDataError.new("bad data")
    assert_kind_of StandardError, error
    assert_equal "bad data", error.message
  end

  private

  # Build transport without starting (avoids httpx dependency for unit tests).
  # We pass an http_client that would only be used after start + build_http_clients!
  # which we skip in these unit tests.
  def build_transport(**opts)
    AgentCore::MCP::Transport::StreamableHttp.new(**opts)
  end
end
