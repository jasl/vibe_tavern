# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Tools::RegistryTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../../../fixtures/skills", __dir__)

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

  def test_register_mcp_client_with_server_id_uses_safe_names_and_forwards_execute
    client = FakeMcpClient.new(
      pages: {
        nil => { "tools" => [{ "name" => "tool.a", "description" => "A", "inputSchema" => {} }] },
      },
      call_result: { "content" => [{ "type" => "text", "text" => "ok" }], "isError" => false },
    )

    server_id = "my.server"
    @registry.register_mcp_client(client, server_id: server_id)

    local_name = AgentCore::MCP::ToolAdapter.local_tool_name(server_id: server_id, remote_tool_name: "tool.a")
    assert @registry.include?(local_name)

    result = @registry.execute(name: local_name, arguments: { "x" => 1 })
    assert_equal "ok", result.text
    refute result.error?

    assert_equal [{ name: "tool.a", arguments: { "x" => 1 } }], client.call_calls
  end

  def test_register_mcp_client_server_id_ignores_prefix_and_warns_once
    client = FakeMcpClient.new(
      pages: {
        nil => { "tools" => [{ "name" => "tool_a", "description" => "A", "inputSchema" => {} }] },
      },
      call_result: { "content" => [{ "type" => "text", "text" => "ok" }], "isError" => false },
    )

    assert_output(nil, /ignores prefix/) do
      @registry.register_mcp_client(client, prefix: "legacy_", server_id: "srv")
    end

    local_name = AgentCore::MCP::ToolAdapter.local_tool_name(server_id: "srv", remote_tool_name: "tool_a")
    assert @registry.include?(local_name)
    refute @registry.include?("legacy_tool_a")
  end

  def test_register_mcp_client_with_server_id_raises_on_mapped_name_collision
    client = FakeMcpClient.new(
      pages: {
        nil => {
          "tools" => [
            { "name" => "tool.a", "description" => "A", "inputSchema" => {} },
            { "name" => "tool_a", "description" => "B", "inputSchema" => {} },
          ],
        },
      },
      call_result: { "content" => [{ "type" => "text", "text" => "ok" }], "isError" => false },
    )

    err =
      assert_raises(ArgumentError) do
        @registry.register_mcp_client(client, server_id: "srv")
      end

    assert_match(/MCP tool name collision/, err.message)
  end

  def test_register_skills_store_registers_skills_tools
    store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [FIXTURES_DIR])
    @registry.register_skills_store(store)

    assert @registry.include?("skills.list")
    assert @registry.include?("skills.load")
    assert @registry.include?("skills.read_file")

    result = @registry.execute(name: "skills.list", arguments: {})
    refute result.error?

    require "json"
    json = JSON.parse(result.text)
    names = json.fetch("skills").map { |s| s.fetch("name") }
    assert_includes names, "example-skill"
    assert_includes names, "another-skill"
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

  def test_execute_mcp_tool_preserves_structured_content_metadata
    client = FakeMcpClient.new(
      pages: {
        nil => { "tools" => [{ "name" => "structured", "description" => "returns structured", "inputSchema" => {} }] },
      },
      call_result: {
        "content" => [{ "type" => "text", "text" => "ok" }],
        "structuredContent" => { "answer" => 42 },
      },
    )

    @registry.register_mcp_client(client)
    result = @registry.execute(name: "structured", arguments: {})

    assert_equal({ structured_content: { "answer" => 42 } }, result.metadata)
  end

  def test_execute_mcp_tool_converts_image_blocks_to_content_blocks
    client = FakeMcpClient.new(
      pages: {
        nil => { "tools" => [{ "name" => "image", "description" => "returns image", "inputSchema" => {} }] },
      },
      call_result: {
        "content" => [
          { "type" => "image", "data" => "QUJD", "mime_type" => "image/png" },
        ],
        "isError" => false,
      },
    )

    @registry.register_mcp_client(client)
    result = @registry.execute(name: "image", arguments: {})

    assert result.has_non_text_content?
    blocks = result.to_content_blocks
    assert_instance_of AgentCore::ImageContent, blocks.first
    assert_equal :base64, blocks.first.source_type
    assert_equal "QUJD", blocks.first.data
    assert_equal "image/png", blocks.first.media_type
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
