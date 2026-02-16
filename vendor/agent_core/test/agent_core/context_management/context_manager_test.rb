# frozen_string_literal: true

require "test_helper"

class AgentCore::ContextManagement::ContextManagerTest < Minitest::Test
  def test_build_prompt_applies_prompt_injections
    agent =
      AgentCore::Agent.build do |b|
        b.provider = MockProvider.new
        b.system_prompt = "BASE"
        b.prompt_injection_source_specs = [{ type: "provided" }]
      end

    manager =
      AgentCore::ContextManagement::ContextManager.new(
        agent: agent,
        conversation_state: agent.conversation_state,
      )

    ctx =
      AgentCore::ExecutionContext.from(
        {
          prompt_injections: [
            { target: :system_section, content: "SYS_INJECT", order: 300 },
            { target: :preamble_message, role: :user, content: "PREAMBLE", order: 10 },
          ],
        }
      )

    prompt = manager.build_prompt(user_message: "Hello", execution_context: ctx)

    assert_includes prompt.system_prompt, "SYS_INJECT"
    assert_equal 2, prompt.messages.size
    assert_equal "PREAMBLE", prompt.messages[0].text
    assert_equal "Hello", prompt.messages[1].text
  end

  def test_build_prompt_filters_injections_by_prompt_mode
    agent =
      AgentCore::Agent.build do |b|
        b.provider = MockProvider.new
        b.system_prompt = "BASE"
        b.prompt_injection_source_specs = [{ type: "provided" }]
      end

    manager =
      AgentCore::ContextManagement::ContextManager.new(
        agent: agent,
        conversation_state: agent.conversation_state,
      )

    ctx =
      AgentCore::ExecutionContext.from(
        {
          prompt_mode: :minimal,
          prompt_injections: [
            { target: :system_section, content: "FULL_ONLY", order: 10, prompt_modes: [:full] },
            { target: :system_section, content: "MIN_ONLY", order: 20, prompt_modes: [:minimal] },
          ],
        }
      )

    prompt = manager.build_prompt(user_message: "Hello", execution_context: ctx)

    refute_includes prompt.system_prompt, "FULL_ONLY"
    assert_includes prompt.system_prompt, "MIN_ONLY"
  end
end
