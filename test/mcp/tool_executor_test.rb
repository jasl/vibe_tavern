# frozen_string_literal: true

require_relative "test_helper"

require "rbconfig"

class MCPToolExecutorTest < Minitest::Test
  def build_registry
    fixture = File.expand_path("../fixtures/mcp_fake_server.rb", __dir__)

    server =
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "fake",
        command: RbConfig.ruby,
        args: [fixture],
        env: {},
        chdir: nil,
        protocol_version: "2024-11-05",
        client_info: { "name" => "test", "version" => "0" },
        capabilities: {},
        timeout_s: 5.0,
      )

    TavernKit::VibeTavern::Tools::MCP::ToolRegistryBuilder.new(servers: [server]).build
  end

  def test_tool_executor_wraps_envelope_and_builds_text
    result = build_registry

    remote_names = result.mapping.values.map { |v| v.fetch(:remote_tool_name) }.sort
    assert_includes remote_names, "echo"
    assert_includes remote_names, "mixed.content"

    local_echo =
      result.mapping.keys.find do |k|
        entry = result.mapping.fetch(k)
        entry[:remote_tool_name] == "echo"
      end
    refute_nil local_echo

    executor =
      TavernKit::VibeTavern::Tools::MCP::ToolExecutor.new(
        clients: result.clients,
        mapping: result.mapping,
        max_bytes: 200_000,
      )

    envelope = executor.call(name: local_echo, args: { "text" => "hello" })
    assert_equal true, envelope.fetch(:ok)

    data = envelope.fetch(:data)
    assert data.fetch(:text).include?("hello")

    mcp = data.fetch(:mcp)
    assert_equal "fake", mcp.fetch(:server_id)
    assert_equal "echo", mcp.fetch(:remote_tool_name)
    assert_equal({ "tool" => "echo", "arguments" => { "text" => "hello" } }, mcp.fetch(:structured_content))
  ensure
    Array(result&.clients&.values).each do |client|
      begin
        client.close
      rescue StandardError
        nil
      end
    end
  end

  def test_tool_executor_sets_ok_false_when_is_error_true
    result = build_registry

    local_echo =
      result.mapping.keys.find do |k|
        entry = result.mapping.fetch(k)
        entry[:remote_tool_name] == "echo"
      end
    refute_nil local_echo

    executor =
      TavernKit::VibeTavern::Tools::MCP::ToolExecutor.new(
        clients: result.clients,
        mapping: result.mapping,
        max_bytes: 200_000,
      )

    envelope = executor.call(name: local_echo, args: { "text" => "hello", "mode" => "error" })
    assert_equal false, envelope.fetch(:ok)
    assert_equal "MCP_TOOL_ERROR", envelope.fetch(:errors).first.fetch(:code)
  ensure
    Array(result&.clients&.values).each do |client|
      begin
        client.close
      rescue StandardError
        nil
      end
    end
  end
end
