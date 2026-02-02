require "test_helper"

class VibeTavernLiquidMacrosAssignsTest < ActiveSupport::TestCase
  test "builds a minimal assigns hash from context" do
    character =
      TavernKit::Character.create(
        name: "Seraphina",
        nickname: "Sera",
        description: "Desc",
        personality: "Pers",
        scenario: "Scen",
        system_prompt: "SYS",
        post_history_instructions: "PHI",
        mes_example: "EX",
      )

    user = TavernKit::User.new(name: "Alice", persona: "A curious adventurer")

    runtime =
      TavernKit::Runtime::Base.build(
        { "chatIndex" => 1, "messageIndex" => 2, "model" => "gpt-x", "role" => "assistant" },
        type: :app,
      )

    ctx = TavernKit::Prompt::Context.new(character: character, user: user, runtime: runtime)

    assigns = TavernKit::VibeTavern::LiquidMacros::Assigns.build(ctx)

    assert_equal "Sera", assigns["char"]
    assert_equal "Alice", assigns["user"]
    assert_equal "Desc", assigns["description"]
    assert_equal "Pers", assigns["personality"]
    assert_equal "Scen", assigns["scenario"]
    assert_equal "A curious adventurer", assigns["persona"]
    assert_equal "SYS", assigns["system_prompt"]
    assert_equal "PHI", assigns["post_history_instructions"]
    assert_equal "EX", assigns["mes_examples"]

    assert_equal 1, assigns["chat_index"]
    assert_equal 2, assigns["message_index"]
    assert_equal "gpt-x", assigns["model"]
    assert_equal "assistant", assigns["role"]

    assert_equal({ "chat_index" => 1, "message_index" => 2, "model" => "gpt-x", "role" => "assistant" }, assigns["runtime"])
  end

  test "derives runtime from ctx[:runtime] when ctx.runtime is not set" do
    ctx = TavernKit::Prompt::Context.new
    ctx[:runtime] = { "chatIndex" => 7 }

    assigns = TavernKit::VibeTavern::LiquidMacros::Assigns.build(ctx)

    assert_equal 7, assigns["chat_index"]
    assert_equal({ "chat_index" => 7 }, assigns["runtime"])
  end
end
