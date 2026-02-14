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
    ) { |args, context:| AgentCore::Resources::Tools::ToolResult.success(text: args.fetch(:text, "")) }
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

# Tool and ToolResult tests live in their dedicated files:
# test/agent_core/resources/tools/tool_test.rb
# test/agent_core/resources/tools/tool_result_test.rb
