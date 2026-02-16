# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Tools::ToolTest < Minitest::Test
  def test_basic_attributes
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "read",
      description: "Read a file",
      parameters: { type: "object" },
      metadata: { category: "io" },
    ) { |_args| nil }

    assert_equal "read", tool.name
    assert_equal "Read a file", tool.description
    assert_equal({ type: "object" }, tool.parameters)
    assert_equal({ category: "io" }, tool.metadata)
  end

  def test_name_frozen
    tool = AgentCore::Resources::Tools::Tool.new(name: "read", description: "d")
    assert tool.name.frozen?
  end

  def test_defaults
    tool = AgentCore::Resources::Tools::Tool.new(name: "t", description: "d")
    assert_equal({}, tool.parameters)
    assert_equal({}, tool.metadata)
  end

  def test_call_executes_handler
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "echo",
      description: "Echo text",
    ) { |args, **| AgentCore::Resources::Tools::ToolResult.success(text: args.fetch("text")) }

    result = tool.call({ "text" => "hello" })
    assert_equal "hello", result.text
  end

  def test_call_passes_context
    captured_context = nil
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "t", description: "d",
    ) { |_args, context:| captured_context = context; AgentCore::Resources::Tools::ToolResult.success(text: "ok") }

    tool.call({}, context: { user: "alice" })
    assert_instance_of AgentCore::ExecutionContext, captured_context
    assert_equal({ user: "alice" }, captured_context.attributes)
  end

  def test_call_without_handler_raises
    tool = AgentCore::Resources::Tools::Tool.new(name: "t", description: "d")
    assert_raises(AgentCore::Error) { tool.call({}) }
  end

  def test_call_handler_error_returns_tool_result_error
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "bad", description: "d",
    ) { |_args, context:| raise "boom" }

    result = tool.call({})
    assert result.error?
    refute_includes result.text, "boom"
    assert_includes result.text, "RuntimeError"

    debug_result = tool.call({}, tool_error_mode: :debug)
    assert debug_result.error?
    assert_includes debug_result.text, "boom"
  end

  def test_call_agent_core_error_reraises
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "bad", description: "d",
    ) { |_args, context:| raise AgentCore::ToolNotFoundError.new("gone", tool_name: "bad") }

    assert_raises(AgentCore::ToolNotFoundError) { tool.call({}) }
  end

  def test_to_definition
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "read", description: "Read a file", parameters: { type: "object" },
    )
    defn = tool.to_definition

    assert_equal "read", defn[:name]
    assert_equal "Read a file", defn[:description]
    assert_equal({ type: "object" }, defn[:parameters])
  end

  def test_to_anthropic
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "read", description: "Read a file", parameters: { type: "object" },
    )
    defn = tool.to_anthropic

    assert_equal "read", defn[:name]
    assert_equal({ type: "object" }, defn[:input_schema])
  end

  def test_to_openai
    tool = AgentCore::Resources::Tools::Tool.new(
      name: "read", description: "Read a file", parameters: { type: "object" },
    )
    defn = tool.to_openai

    assert_equal "function", defn[:type]
    assert_equal "read", defn[:function][:name]
    assert_equal({ type: "object" }, defn[:function][:parameters])
  end
end
