# frozen_string_literal: true

module AgentCore
  module MCP
    DEFAULT_PROTOCOL_VERSION = "2025-11-25"
    SUPPORTED_PROTOCOL_VERSIONS = ["2025-11-25", "2025-03-26"].freeze
    DEFAULT_TIMEOUT_S = 10.0
    DEFAULT_MAX_BYTES = 200_000

    HTTP_ACCEPT_POST = "application/json, text/event-stream"
    HTTP_ACCEPT_GET = "text/event-stream"

    MCP_SESSION_ID_HEADER = "MCP-Session-Id"
    MCP_PROTOCOL_VERSION_HEADER = "MCP-Protocol-Version"
    LAST_EVENT_ID_HEADER = "Last-Event-ID"
  end
end
