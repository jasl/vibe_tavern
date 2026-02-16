# frozen_string_literal: true

require "test_helper"

class AgentCore::ContextManagement::BudgetManagerTest < Minitest::Test
  class FakeTokenCounter
    def count_messages(messages) = Array(messages).size
    def count_tools(tools) = Array(tools).size
  end

  def build_prompt(summary:, turns:, memory_results:)
    messages = []

    if summary && !summary.to_s.strip.empty?
      messages << AgentCore::Message.new(role: :assistant, content: "SUMMARY: #{summary}")
    end

    Array(memory_results).each do |m|
      messages << AgentCore::Message.new(role: :assistant, content: "MEM: #{m}")
    end

    messages.concat(turns.flatten)

    AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "",
      messages: messages,
      tools: [],
      options: {},
    )
  end

  def test_build_prompt_when_token_budget_disabled_does_not_drop_or_persist_state
    chat_history =
      AgentCore::Resources::ChatHistory::InMemory.new(
        [
          AgentCore::Message.new(role: :user, content: "U1"),
          AgentCore::Message.new(role: :assistant, content: "A1"),
        ],
      )

    conversation_state = AgentCore::Resources::ConversationState::InMemory.new

    manager =
      AgentCore::ContextManagement::BudgetManager.new(
        chat_history: chat_history,
        conversation_state: conversation_state,
        provider: MockProvider.new,
        model: "m1",
        token_counter: nil,
        context_window: nil,
      )

    prompt =
      manager.build_prompt(memory_results: %w[m1 m2]) do |summary:, turns:, memory_results:|
        build_prompt(summary: summary, turns: turns, memory_results: memory_results)
      end

    assert_equal ["MEM: m1", "MEM: m2", "U1", "A1"], prompt.messages.map(&:text)
    assert conversation_state.load.empty?
  end

  def test_build_prompt_drops_memory_before_turns
    chat_history =
      AgentCore::Resources::ChatHistory::InMemory.new(
        [
          AgentCore::Message.new(role: :user, content: "U1"),
          AgentCore::Message.new(role: :assistant, content: "A1"),
        ],
      )

    conversation_state = AgentCore::Resources::ConversationState::InMemory.new

    manager =
      AgentCore::ContextManagement::BudgetManager.new(
        chat_history: chat_history,
        conversation_state: conversation_state,
        provider: MockProvider.new,
        model: "m1",
        token_counter: FakeTokenCounter.new,
        context_window: 3,
      )

    prompt =
      manager.build_prompt(memory_results: %w[m1 m2]) do |summary:, turns:, memory_results:|
        build_prompt(summary: summary, turns: turns, memory_results: memory_results)
      end

    assert_equal ["MEM: m1", "U1", "A1"], prompt.messages.map(&:text)
    assert conversation_state.load.empty?
  end

  def test_build_prompt_summarizes_dropped_turns_and_persists_state
    provider =
      MockProvider.new(
        responses: [
          AgentCore::Resources::Provider::Response.new(
            message: AgentCore::Message.new(role: :assistant, content: "NEW SUMMARY"),
            usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 1, output_tokens: 1),
            stop_reason: :end_turn,
          ),
        ],
      )

    chat_history =
      AgentCore::Resources::ChatHistory::InMemory.new(
        [
          AgentCore::Message.new(role: :user, content: "U1"),
          AgentCore::Message.new(role: :assistant, content: "A1"),
          AgentCore::Message.new(role: :user, content: "U2"),
          AgentCore::Message.new(role: :assistant, content: "A2"),
        ],
      )

    conversation_state = AgentCore::Resources::ConversationState::InMemory.new

    manager =
      AgentCore::ContextManagement::BudgetManager.new(
        chat_history: chat_history,
        conversation_state: conversation_state,
        provider: provider,
        model: "m1",
        token_counter: FakeTokenCounter.new,
        context_window: 3,
        auto_compact: true,
      )

    prompt =
      manager.build_prompt(memory_results: []) do |summary:, turns:, memory_results:|
        build_prompt(summary: summary, turns: turns, memory_results: memory_results)
      end

    assert_equal ["SUMMARY: NEW SUMMARY", "U2", "A2"], prompt.messages.map(&:text)

    state = conversation_state.load
    assert_equal "NEW SUMMARY", state.summary
    assert_equal 2, state.cursor
    assert_equal 1, state.compaction_count

    assert_equal 1, provider.calls.size
  end

  def test_build_prompt_clears_stale_state_when_cursor_exceeds_history
    chat_history =
      AgentCore::Resources::ChatHistory::InMemory.new(
        [
          AgentCore::Message.new(role: :user, content: "U1"),
          AgentCore::Message.new(role: :assistant, content: "A1"),
        ],
      )

    stale =
      AgentCore::Resources::ConversationState::State.new(
        summary: "OLD",
        cursor: 10,
        compaction_count: 5,
      )
    conversation_state = AgentCore::Resources::ConversationState::InMemory.new(stale)

    manager =
      AgentCore::ContextManagement::BudgetManager.new(
        chat_history: chat_history,
        conversation_state: conversation_state,
        provider: MockProvider.new,
        model: "m1",
        token_counter: nil,
        context_window: nil,
      )

    prompt =
      manager.build_prompt(memory_results: []) do |summary:, turns:, memory_results:|
        build_prompt(summary: summary, turns: turns, memory_results: memory_results)
      end

    assert_equal ["U1", "A1"], prompt.messages.map(&:text)

    cleared = conversation_state.load
    assert_nil cleared.summary
    assert_equal 0, cleared.cursor
    assert_equal 0, cleared.compaction_count
  end
end
