# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::PromptInjections::Sources::ProvidedTest < Minitest::Test
  def test_reads_items_from_execution_context_attributes
    source = AgentCore::Resources::PromptInjections::Sources::Provided.new(context_key: :my_injections)

    ctx =
      AgentCore::ExecutionContext.from(
        {
          my_injections: [
            { target: :system_section, content: "SYS", order: 1 },
            { target: :preamble_message, role: :user, content: "PRE", order: 2, max_bytes: 10 },
          ],
        }
      )

    items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)
    assert_equal 2, items.size

    assert_equal :system_section, items[0].target
    assert_equal "SYS", items[0].content

    assert_equal :preamble_message, items[1].target
    assert_equal :user, items[1].role
    assert_includes items[1].content, "PRE"
  end
end
