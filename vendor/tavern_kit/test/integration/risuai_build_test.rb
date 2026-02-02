# frozen_string_literal: true

require "test_helper"

class RisuaiBuildTest < Minitest::Test
  def test_risuai_pipeline_end_to_end
    character = TavernKit::Character.create(name: "Char", description: "DESC")
    user = TavernKit::User.new(name: "User", persona: "PERSONA")

    history = TavernKit::ChatHistory::InMemory.new(
      [
        { role: :user, content: "prev user" },
        { role: :assistant, content: "prev assistant" },
      ],
    )

    template = [
      { "type" => "plain", "type2" => "main", "role" => "system", "text" => "MAIN {{position::lorebook}}" },
      { "type" => "persona", "innerFormat" => "P: {{slot}}" },
      { "type" => "description" },
      { "type" => "lorebook" },
      { "type" => "chat", "rangeStart" => 0, "rangeEnd" => "end" },
      { "type" => "postEverything" },
    ]

    lore_book = TavernKit::Lore::Book.new(
      entries: [
        # For {{position::lorebook}}
        TavernKit::Lore::Entry.new(keys: ["hi"], content: "@@position pt_lorebook\nP1", insertion_order: 100),
        # For inject_at main
        TavernKit::Lore::Entry.new(keys: ["hi"], content: "@@inject_at main\nINJECT", insertion_order: 90),
        # Normal lorebook content
        TavernKit::Lore::Entry.new(keys: ["hi"], content: "L1", insertion_order: 80),
      ],
    )

    plan = TavernKit::RisuAI.build do
      preset({ "promptTemplate" => template })
      character(character)
      user(user)
      history(history)
      message("hi")
      lore_book(lore_book)
      runtime({ chat_index: 1 })
    end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "system", msgs[0][:role]
    assert_equal "MAIN P1 INJECT", msgs[0][:content]

    assert_equal "system", msgs[1][:role]
    assert_equal "P: PERSONA", msgs[1][:content]

    assert_equal "system", msgs[2][:role]
    assert_includes msgs[2][:content], "DESC"

    assert_equal "system", msgs[3][:role]
    assert_equal "L1", msgs[3][:content]

    assert_equal "user", msgs[4][:role]
    assert_equal "prev user", msgs[4][:content]
    assert_equal "assistant", msgs[5][:role]
    assert_equal "prev assistant", msgs[5][:content]

    assert_equal "user", msgs[6][:role]
    assert_equal "hi", msgs[6][:content]
  end
end
