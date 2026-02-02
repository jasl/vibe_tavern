# frozen_string_literal: true

require "test_helper"

class RisuaiMemoryTest < Minitest::Test
  class TestMemoryAdapter < TavernKit::RisuAI::Memory::Base
    attr_reader :last_input

    def integrate(input, context:)
      @last_input = input

      block = TavernKit::Prompt::Block.new(
        role: :system,
        content: "MEMORY",
        token_budget_group: :memory,
        metadata: { risuai: { source: "test" } },
        removable: true,
      )

      TavernKit::RisuAI::Memory::MemoryResult.new(blocks: [block], tokens_used: 6, compression_type: :test)
    end
  end

  def test_memory_blocks_are_inserted_via_memory_card
    adapter = TestMemoryAdapter.new

    template = [
      { "type" => "plain", "type2" => "main", "role" => "system", "text" => "MAIN" },
      { "type" => "memory" },
      { "type" => "chat", "rangeStart" => 0, "rangeEnd" => "end" },
    ]

    plan = TavernKit::RisuAI.build do
      preset({ "promptTemplate" => template })
      character(TavernKit::Character.create(name: "Char"))
      user(TavernKit::User.new(name: "User"))
      history([{ role: :user, content: "hi" }])
      meta(:risuai_memory_adapter, adapter)
      meta(:risuai_memory_input, { summaries: ["S1"], pinned_memories: ["P1"], metadata: { "m" => 1 }, budget_tokens: 123 })
    end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal ["MAIN", "MEMORY", "hi"], msgs.map { |m| m[:content] }

    assert_instance_of TavernKit::RisuAI::Memory::MemoryInput, adapter.last_input
    assert_equal ["S1"], adapter.last_input.summaries
    assert_equal ["P1"], adapter.last_input.pinned_memories
    assert_equal({ "m" => 1 }, adapter.last_input.metadata)
    assert_equal 123, adapter.last_input.budget_tokens
  end
end
