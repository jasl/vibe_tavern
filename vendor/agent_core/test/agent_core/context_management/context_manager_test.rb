# frozen_string_literal: true

require "test_helper"

class AgentCore::AgentPromptInjectionsTest < Minitest::Test
  def build_agent(provider:)
    AgentCore::Agent.build do |b|
      b.provider = provider
      b.system_prompt = "BASE"
      b.prompt_injection_source_specs = [{ type: "provided" }]
    end
  end

  def test_agent_chat_applies_prompt_injections
    provider = MockProvider.new
    agent = build_agent(provider: provider)

    ctx = {
      prompt_injections: [
        { target: :system_section, content: "SYS_INJECT", order: 300 },
        { target: :preamble_message, role: :user, content: "PREAMBLE", order: 10 },
      ],
    }

    agent.chat("Hello", context: ctx)

    request = provider.calls.first
    messages = request.fetch(:messages)

    assert_equal :system, messages.first.role
    assert_includes messages.first.text, "SYS_INJECT"

    assert_equal "PREAMBLE", messages[1].text
    assert_equal "Hello", messages[2].text
  end

  def test_agent_chat_filters_prompt_injections_by_prompt_mode
    provider = MockProvider.new
    agent = build_agent(provider: provider)

    ctx = {
      prompt_mode: :minimal,
      prompt_injections: [
        { target: :system_section, content: "FULL_ONLY", order: 10, prompt_modes: [:full] },
        { target: :system_section, content: "MIN_ONLY", order: 20, prompt_modes: [:minimal] },
      ],
    }

    agent.chat("Hello", context: ctx)

    request = provider.calls.first
    system_message = request.fetch(:messages).first

    refute_includes system_message.text, "FULL_ONLY"
    assert_includes system_message.text, "MIN_ONLY"
  end
end
