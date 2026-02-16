# frozen_string_literal: true

# MCP (Model Context Protocol) client stack.
#
# Provides transport abstractions, JSON-RPC client, and high-level
# MCP session management.
#
# NOTE: StreamableHttp transport is NOT required here.
# It lazy-loads httpx and should only be loaded when explicitly needed.
# Use: require "agent_core/mcp/transport/streamable_http"

require_relative "errors"
require_relative "utils"

require_relative "mcp/constants"
require_relative "mcp/sse_parser"
require_relative "mcp/transport/base"
require_relative "mcp/transport/stdio"
# StreamableHttp intentionally NOT required (httpx is optional)
require_relative "mcp/json_rpc_client"
require_relative "mcp/client"
require_relative "mcp/server_config"
require_relative "mcp/tool_adapter"
