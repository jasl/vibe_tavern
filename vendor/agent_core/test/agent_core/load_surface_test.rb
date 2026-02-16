# frozen_string_literal: true

require "test_helper"

require "open3"
require "rbconfig"

class AgentCore::LoadSurfaceTest < Minitest::Test
  def test_require_agent_core_does_not_load_mcp_stack
    gem_root = File.expand_path("../..", __dir__)

    code = <<~RUBY
      require "agent_core"

      mcp_loaded = defined?(AgentCore::MCP::Client) || defined?(AgentCore::MCP::ToolAdapter)
      exit(mcp_loaded ? 1 : 0)
    RUBY

    _stdout, stderr, status =
      Open3.capture3(
        "bundle",
        "exec",
        RbConfig.ruby,
        "-I",
        "lib",
        "-e",
        code,
        chdir: gem_root
      )

    assert status.success?, "expected MCP to be opt-in (stderr=#{stderr.inspect})"
  end
end
