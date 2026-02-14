# frozen_string_literal: true

require "test_helper"

class AgentCore::MCP::ConstantsTest < Minitest::Test
  def test_default_protocol_version
    assert_equal "2025-11-25", AgentCore::MCP::DEFAULT_PROTOCOL_VERSION
  end

  def test_supported_protocol_versions
    versions = AgentCore::MCP::SUPPORTED_PROTOCOL_VERSIONS
    assert_includes versions, "2025-11-25"
    assert_includes versions, "2025-06-18"
    assert_includes versions, "2025-03-26"
    assert_includes versions, "2024-11-05"
    assert versions.frozen?
  end

  def test_default_timeout
    assert_equal 10.0, AgentCore::MCP::DEFAULT_TIMEOUT_S
  end

  def test_http_headers
    assert_equal "MCP-Session-Id", AgentCore::MCP::MCP_SESSION_ID_HEADER
    assert_equal "MCP-Protocol-Version", AgentCore::MCP::MCP_PROTOCOL_VERSION_HEADER
    assert_equal "Last-Event-ID", AgentCore::MCP::LAST_EVENT_ID_HEADER
  end

  def test_http_accept_headers
    assert_includes AgentCore::MCP::HTTP_ACCEPT_POST, "application/json"
    assert_includes AgentCore::MCP::HTTP_ACCEPT_POST, "text/event-stream"
    assert_equal "text/event-stream", AgentCore::MCP::HTTP_ACCEPT_GET
  end
end
