# frozen_string_literal: true

require_relative "test_helper"

class MCPToolAdapterTest < Minitest::Test
  def test_local_tool_name_sanitizes_and_replaces_dots
    name =
      TavernKit::VibeTavern::Tools::MCP::ToolAdapter.local_tool_name(
        server_id: "srv.one",
        remote_tool_name: "foo.bar",
      )

    assert_equal "mcp_srv_one__foo_bar", name
  end

  def test_local_tool_name_limits_length_with_hash_suffix
    long_server = "s" * 80
    long_tool = "t" * 200

    name =
      TavernKit::VibeTavern::Tools::MCP::ToolAdapter.local_tool_name(
        server_id: long_server,
        remote_tool_name: long_tool,
      )

    assert_operator name.length, :<=, 128

    name2 =
      TavernKit::VibeTavern::Tools::MCP::ToolAdapter.local_tool_name(
        server_id: long_server,
        remote_tool_name: long_tool,
      )

    assert_equal name, name2
  end
end
