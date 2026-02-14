# frozen_string_literal: true

require "test_helper"

class AgentCore::MCP::ToolAdapterTest < Minitest::Test
  def test_local_tool_name_simple
    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: "my_server",
      remote_tool_name: "read_file",
    )

    assert_equal "mcp_my_server__read_file", name
  end

  def test_local_tool_name_dots_replaced
    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: "com.example.server",
      remote_tool_name: "read.file",
    )

    assert_equal "mcp_com_example_server__read_file", name
  end

  def test_local_tool_name_special_chars_replaced
    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: "my server!",
      remote_tool_name: "read@file#v2",
    )

    assert_equal "mcp_my_server___read_file_v2", name
  end

  def test_local_tool_name_max_128_chars
    long_server = "a" * 100
    long_tool = "b" * 100

    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: long_server,
      remote_tool_name: long_tool,
    )

    assert name.length <= 128, "Name should be <= 128 chars, got #{name.length}"
  end

  def test_local_tool_name_short_enough_no_sha
    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: "s",
      remote_tool_name: "t",
    )

    assert_equal "mcp_s__t", name
    refute_match(/_[a-f0-9]{10}\z/, name)
  end

  def test_local_tool_name_sha_suffix_for_overflow
    long_server = "a" * 70
    long_tool = "b" * 70

    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: long_server,
      remote_tool_name: long_tool,
    )

    assert name.length <= 128
    assert_match(/_[a-f0-9]{10}\z/, name)
  end

  def test_local_tool_name_blank_fallback
    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: "",
      remote_tool_name: "",
    )

    assert_equal "mcp_server__tool", name
  end

  def test_local_tool_name_deterministic
    args = { server_id: "test", remote_tool_name: "read_file" }

    name1 = AgentCore::MCP::ToolAdapter.local_tool_name(**args)
    name2 = AgentCore::MCP::ToolAdapter.local_tool_name(**args)

    assert_equal name1, name2
  end

  def test_mapping_entry
    entry = AgentCore::MCP::ToolAdapter.mapping_entry(
      server_id: "my_server",
      remote_tool_name: "read_file",
    )

    assert_equal({ server_id: "my_server", remote_tool_name: "read_file" }, entry)
  end

  def test_mapping_entry_converts_to_string
    entry = AgentCore::MCP::ToolAdapter.mapping_entry(
      server_id: :my_server,
      remote_tool_name: :read_file,
    )

    assert_equal "my_server", entry[:server_id]
    assert_equal "read_file", entry[:remote_tool_name]
  end

  def test_local_tool_name_hyphens_preserved
    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: "my-server",
      remote_tool_name: "read-file",
    )

    assert_equal "mcp_my-server__read-file", name
  end

  def test_local_tool_name_nil_values
    name = AgentCore::MCP::ToolAdapter.local_tool_name(
      server_id: nil,
      remote_tool_name: nil,
    )

    assert_equal "mcp_server__tool", name
  end
end
