# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptBuilder::ContextTest < Minitest::Test
  def test_defaults
    ctx = AgentCore::PromptBuilder::Context.new

    assert_equal "", ctx.system_prompt
    assert_nil ctx.chat_history
    assert_nil ctx.tools_registry
    assert_equal [], ctx.memory_results
    assert_nil ctx.user_message
    assert_equal({}, ctx.variables)
    assert_equal({}, ctx.agent_config)
    assert_nil ctx.tool_policy
  end

  def test_custom_values
    ctx = AgentCore::PromptBuilder::Context.new(
      system_prompt: "Be helpful",
      user_message: "Hello",
      variables: { name: "Alice" },
      agent_config: { model: "claude" },
    )

    assert_equal "Be helpful", ctx.system_prompt
    assert_equal "Hello", ctx.user_message
    assert_equal({ name: "Alice" }, ctx.variables)
    assert_equal({ model: "claude" }, ctx.agent_config)
  end

  def test_variables_frozen
    ctx = AgentCore::PromptBuilder::Context.new(variables: { a: 1 })
    assert ctx.variables.frozen?
  end

  def test_agent_config_frozen
    ctx = AgentCore::PromptBuilder::Context.new(agent_config: { x: 1 })
    assert ctx.agent_config.frozen?
  end

  def test_nil_variables_becomes_empty_hash
    ctx = AgentCore::PromptBuilder::Context.new(variables: nil)
    assert_equal({}, ctx.variables)
    assert ctx.variables.frozen?
  end

  def test_nil_agent_config_becomes_empty_hash
    ctx = AgentCore::PromptBuilder::Context.new(agent_config: nil)
    assert_equal({}, ctx.agent_config)
    assert ctx.agent_config.frozen?
  end

  def test_memory_results_coerced_to_array
    ctx = AgentCore::PromptBuilder::Context.new(memory_results: nil)
    assert_equal [], ctx.memory_results
  end
end
