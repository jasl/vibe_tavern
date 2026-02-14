# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Tools::RegistryTest < Minitest::Test
  class FakeMcpClient
    def initialize(pages:, call_result:)
      @pages = pages
      @call_result = call_result
      @list_calls = []
      @call_calls = []
    end

    attr_reader :list_calls, :call_calls

    def list_tools(cursor: nil, timeout_s: nil)
      _timeout_s = timeout_s
      @list_calls << cursor
      @pages.fetch(cursor, { "tools" => [] })
    end

    def call_tool(name:, arguments: {}, timeout_s: nil)
      _timeout_s = timeout_s
      @call_calls << { name: name, arguments: arguments }
      @call_result
    end
  end

  def setup
    @registry = AgentCore::Resources::Tools::Registry.new
    @echo_tool = AgentCore::Resources::Tools::Tool.new(
      name: "echo",
      description: "Echo the input",
      parameters: {
        type: "object",
        properties: { text: { type: "string" } },
        required: ["text"],
      }
    ) { |args, **| AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text", "")) }
  end

  def test_register_and_find
    @registry.register(@echo_tool)
    assert @registry.include?("echo")
    assert_equal @echo_tool, @registry.find("echo")
  end

  def test_register_many
    tool2 = AgentCore::Resources::Tools::Tool.new(name: "noop", description: "no-op") { }
    @registry.register_many([@echo_tool, tool2])
    assert_equal 2, @registry.size
  end

  def test_execute_native_tool
    @registry.register(@echo_tool)
    result = @registry.execute(name: "echo", arguments: { "text" => "hello" })
    assert_equal "hello", result.text
    refute result.error?
  end

  def test_execute_unknown_tool_raises
    assert_raises(AgentCore::ToolNotFoundError) do
      @registry.execute(name: "nonexistent", arguments: {})
    end
  end

  def test_register_mcp_client_registers_all_pages
    client = FakeMcpClient.new(
      pages: {
        nil => {
          "tools" => [{ "name" => "tool_a", "description" => "A", "inputSchema" => {} }],
          "nextCursor" => "page2",
        },
        "page2" => {
          "tools" => [{ "name" => "tool_b", "description" => "B", "inputSchema" => {} }],
        },
      },
      call_result: { "content" => [{ "type" => "text", "text" => "ok" }], "isError" => false },
    )

    @registry.register_mcp_client(client, prefix: "mcp_")

    assert @registry.include?("mcp_tool_a")
    assert @registry.include?("mcp_tool_b")
    assert_equal [nil, "page2"], client.list_calls
  end

  def test_execute_mcp_tool_normalizes_is_error
    client = FakeMcpClient.new(
      pages: {
        nil => { "tools" => [{ "name" => "fail", "description" => "fails", "inputSchema" => {} }] },
      },
      call_result: { "content" => [{ "type" => "text", "text" => "oops" }], "isError" => true },
    )

    @registry.register_mcp_client(client)
    result = @registry.execute(name: "fail", arguments: {})

    assert_equal "oops", result.text
    assert_equal true, result.error?
  end

  def test_definitions_generic
    @registry.register(@echo_tool)
    defs = @registry.definitions
    assert_equal 1, defs.size
    assert_equal "echo", defs.first[:name]
    assert_equal "Echo the input", defs.first[:description]
  end

  def test_definitions_anthropic_format
    @registry.register(@echo_tool)
    defs = @registry.definitions(format: :anthropic)
    assert_equal "echo", defs.first[:name]
    assert defs.first.key?(:input_schema)
  end

  def test_definitions_openai_format
    @registry.register(@echo_tool)
    defs = @registry.definitions(format: :openai)
    assert_equal "function", defs.first[:type]
    assert_equal "echo", defs.first[:function][:name]
  end

  def test_tool_names
    @registry.register(@echo_tool)
    assert_equal ["echo"], @registry.tool_names
  end

  def test_clear
    @registry.register(@echo_tool)
    @registry.clear
    assert_equal 0, @registry.size
  end
end

# Tool and ToolResult tests live in their dedicated files:
# test/agent_core/resources/tools/tool_test.rb
# test/agent_core/resources/tools/tool_result_test.rb
