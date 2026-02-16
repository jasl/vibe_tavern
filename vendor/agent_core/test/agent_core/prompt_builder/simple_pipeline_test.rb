# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptBuilder::SimplePipelineTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../../fixtures/skills", __dir__)

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
      tool_policy: AgentCore::Resources::Tools::Policy::AllowAll.new,
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

  def test_injects_available_skills_fragment
    store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [FIXTURES_DIR])
    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      user_message: "Hi",
      skills_store: store
    )

    prompt = @pipeline.build(context: context)

    assert_includes prompt.system_prompt, "<available_skills>"
    assert_includes prompt.system_prompt, "example-skill"
    refute_includes prompt.system_prompt, "location="
  end

  def test_injects_system_sections_in_order_with_memory_and_skills
    store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [FIXTURES_DIR])

    memory_entries = [
      AgentCore::Resources::Memory::Entry.new(id: "1", content: "MEM"),
    ]

    items = [
      AgentCore::Resources::PromptInjections::Item.new(
        target: :system_section,
        content: "INJECT_2",
        order: 500,
      ),
      AgentCore::Resources::PromptInjections::Item.new(
        target: :system_section,
        content: "INJECT_1",
        order: 300,
      ),
    ]

    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "BASE",
      memory_results: memory_entries,
      prompt_injection_items: items,
      skills_store: store,
      user_message: "Hi",
    )

    prompt = @pipeline.build(context: context)
    sys = prompt.system_prompt

    idx_mem = sys.index("<relevant_context>")
    idx_i1 = sys.index("INJECT_1")
    idx_i2 = sys.index("INJECT_2")
    idx_skills = sys.index("<available_skills>")

    assert idx_mem && idx_i1 && idx_i2 && idx_skills
    assert_operator idx_mem, :<, idx_i1
    assert_operator idx_i1, :<, idx_i2
    assert_operator idx_i2, :<, idx_skills
  end

  def test_inserts_preamble_messages_before_chat_history
    history = AgentCore::Resources::ChatHistory::InMemory.new
    history.append(AgentCore::Message.new(role: :user, content: "First"))
    history.append(AgentCore::Message.new(role: :assistant, content: "Response"))

    injections = [
      AgentCore::Resources::PromptInjections::Item.new(
        target: :preamble_message,
        role: :user,
        content: "P1",
        order: 10,
      ),
      AgentCore::Resources::PromptInjections::Item.new(
        target: :preamble_message,
        role: :assistant,
        content: "P2",
        order: 20,
      ),
    ]

    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      chat_history: history,
      prompt_injection_items: injections,
      user_message: "Second",
    )

    prompt = @pipeline.build(context: context)

    assert_equal 5, prompt.messages.size
    assert_equal "P1", prompt.messages[0].text
    assert_equal "P2", prompt.messages[1].text
    assert_equal "First", prompt.messages[2].text
    assert_equal "Response", prompt.messages[3].text
    assert_equal "Second", prompt.messages[4].text
  end

  def test_prompt_mode_filters_injection_items
    injections = [
      AgentCore::Resources::PromptInjections::Item.new(
        target: :system_section,
        content: "FULL_ONLY",
        order: 10,
        prompt_modes: [:full],
      ),
      AgentCore::Resources::PromptInjections::Item.new(
        target: :system_section,
        content: "MIN_ONLY",
        order: 20,
        prompt_modes: [:minimal],
      ),
      AgentCore::Resources::PromptInjections::Item.new(
        target: :preamble_message,
        role: :user,
        content: "BOTH",
        order: 30,
        prompt_modes: [:full, :minimal],
      ),
    ]

    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "BASE",
      prompt_mode: :minimal,
      prompt_injection_items: injections,
      user_message: "Hi",
    )

    prompt = @pipeline.build(context: context)

    refute_includes prompt.system_prompt, "FULL_ONLY"
    assert_includes prompt.system_prompt, "MIN_ONLY"
    assert_equal "BOTH", prompt.messages[0].text
  end

  def test_available_skills_fragment_can_include_location
    store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [FIXTURES_DIR])
    context = AgentCore::PromptBuilder::Context.new(
      system_prompt: "You are helpful.",
      user_message: "Hi",
      skills_store: store,
      include_skill_locations: true
    )

    prompt = @pipeline.build(context: context)

    assert_includes prompt.system_prompt, "<available_skills>"
    assert_includes prompt.system_prompt, "location="
  end
end
