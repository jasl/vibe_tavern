# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"

require "tavern_kit"

require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp/errors"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp/transport/stdio"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp/json_rpc_client"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp/client"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp/tool_adapter"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp/tool_registry_builder"
require_relative "../../lib/tavern_kit/vibe_tavern/tools/mcp/tool_executor"
