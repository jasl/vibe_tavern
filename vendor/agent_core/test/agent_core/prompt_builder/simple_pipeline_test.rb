# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptBuilder::SimplePipelineTest < Minitest::Test
  def setup
    @pipeline = AgentCore::PromptBuilder::SimplePipeline.new
  end

  def test_basic_prompt_building
    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      user_message: "Hello!"
    )

    prompt = @pipeline.build(context: context)

    assert_equal "You are helpful.", prompt.system_prompt
    assert_equal 1, prompt.messages.size
    assert_equal "Hello!", prompt.messages.last.text
    assert_equal :user, prompt.messages.last.role
  end

  def test_includes_chat_history
    history = AgentCore::Resources::ChatHistory::InMemory.new
    history.append(AgentCore::Message.new(role: :user, content: "First"))
    history.append(AgentCore::Message.new(role: :assistant, content: "Response"))

    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      chat_history: history,
      user_message: "Second"
    )

    prompt = @pipeline.build(context: context)

    assert_equal 3, prompt.messages.size
    assert_equal "First", prompt.messages[0].text
    assert_equal "Response", prompt.messages[1].text
    assert_equal "Second", prompt.messages[2].text
  end

  def test_injects_memory_context
    memory_entries = [
      AgentCore::Resources::Memory::Entry.new(id: "1", content: "User likes Ruby"),
      AgentCore::Resources::Memory::Entry.new(id: "2", content: "Project uses Rails 8"),
    ]

    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      memory_results: memory_entries,
      user_message: "Tell me about my project"
    )

    prompt = @pipeline.build(context: context)

    assert_includes prompt.system_prompt, "User likes Ruby"
    assert_includes prompt.system_prompt, "Project uses Rails 8"
    assert_includes prompt.system_prompt, "<relevant_context>"
  end

  def test_variable_substitution
    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "Hello {{name}}, you are a {{role}}.",
      variables: { "name" => "Alice", "role" => "developer" },
      user_message: "Hi"
    )

    prompt = @pipeline.build(context: context)

    assert_equal "Hello Alice, you are a developer.", prompt.system_prompt
  end

  def test_includes_tool_definitions
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "read", description: "Read file", parameters: {}) { }
    )

    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      tools_registry: registry,
      user_message: "Hi"
    )

    prompt = @pipeline.build(context: context)

    assert prompt.has_tools?
    assert_equal 1, prompt.tools.size
    assert_equal "read", prompt.tools.first[:name]
  end

  def test_no_tools_when_no_registry
    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      user_message: "Hi"
    )

    prompt = @pipeline.build(context: context)
    refute prompt.has_tools?
  end

  def test_llm_options_from_agent_config
    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      user_message: "Hi",
      agent_config: { llm_options: { temperature: 0.7, model: "test-model" } }
    )

    prompt = @pipeline.build(context: context)
    assert_equal 0.7, prompt.options[:temperature]
    assert_equal "test-model", prompt.options[:model]
  end
end
