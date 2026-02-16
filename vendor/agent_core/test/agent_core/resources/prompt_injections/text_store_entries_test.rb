# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::PromptInjections::Sources::TextStoreEntriesTest < Minitest::Test
  def test_fetches_from_store_and_applies_wrapper
    store = AgentCore::Resources::PromptInjections::TextStore::InMemory.new("k1" => "Hello")

    source =
      AgentCore::Resources::PromptInjections::Sources::TextStoreEntries.new(
        text_store: store,
        entries: [
          {
            key: "k1",
            target: :preamble_message,
            role: :user,
            order: 10,
            wrapper: "BEGIN\n{{content}}\nEND",
          },
        ],
      )

    ctx = AgentCore::ExecutionContext.from({})
    items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)

    assert_equal 1, items.size
    assert_equal :preamble_message, items[0].target
    assert_equal :user, items[0].role
    assert_equal "BEGIN\nHello\nEND", items[0].content
  end

  def test_applies_max_bytes_truncation
    store = AgentCore::Resources::PromptInjections::TextStore::InMemory.new("k1" => ("A" * 200))

    source =
      AgentCore::Resources::PromptInjections::Sources::TextStoreEntries.new(
        text_store: store,
        entries: [
          {
            key: "k1",
            target: :system_section,
            order: 10,
            max_bytes: 40,
          },
        ],
      )

    ctx = AgentCore::ExecutionContext.from({})
    items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)

    assert_equal 1, items.size
    assert_operator items[0].content.bytesize, :<=, 40
    assert_includes items[0].content, "\n...\n"
  end
end
