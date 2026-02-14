# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Tools::RegistryTest < Minitest::Test
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
    ) { |args, context:| AgentCore::Resources::Tools::ToolResult.success(text: args[:text] || args["text"]) }
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
    result = @registry.execute(name: "echo", arguments: { text: "hello" })
    assert_equal "hello", result.text
    refute result.error?
  end

  def test_execute_unknown_tool_raises
    assert_raises(AgentCore::ToolNotFoundError) do
      @registry.execute(name: "nonexistent", arguments: {})
    end
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

class AgentCore::Resources::Tools::ToolTest < Minitest::Test
  def test_tool_execution
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "add",
      description: "Add numbers",
      parameters: {}
    ) { |args, context:| AgentCore::Resources::Tools::ToolResult.success(text: (args[:a].to_i + args[:b].to_i).to_s) }

    result = tool.call({ a: 2, b: 3 })
    assert_equal "5", result.text
  end

  def test_tool_error_handling
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "fail",
      description: "Always fails"
    ) { |args, context:| raise "boom" }

    result = tool.call({})
    assert result.error?
    assert_match(/boom/, result.text)
  end

  def test_no_handler_raises
    tool = AgentCore::Resources::Tools::Tool.new(name: "empty", description: "no handler")
    assert_raises(AgentCore::Error) { tool.call({}) }
  end

  def test_to_definition
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "test",
      description: "test tool",
      parameters: { type: "object" }
    ) { }

    defn = tool.to_definition
    assert_equal "test", defn[:name]
    assert_equal "test tool", defn[:description]
  end
end

class AgentCore::Resources::Tools::ToolResultTest < Minitest::Test
  def test_success
    result = AgentCore::Resources::Tools::ToolResult.success(text: "ok")
    assert_equal "ok", result.text
    refute result.error?
  end

  def test_error
    result = AgentCore::Resources::Tools::ToolResult.error(text: "failed")
    assert_equal "failed", result.text
    assert result.error?
  end

  def test_multi_content
    result = AgentCore::Resources::Tools::ToolResult.with_content([
      { type: "text", text: "line 1" },
      { type: "text", text: "line 2" },
    ])
    assert_equal "line 1\nline 2", result.text
  end
end
