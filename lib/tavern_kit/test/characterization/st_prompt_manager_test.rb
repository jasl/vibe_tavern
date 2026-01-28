# frozen_string_literal: true

require "test_helper"

class StPromptManagerTest < Minitest::Test
  def pending!(reason)
    skip("Pending ST parity: #{reason}")
  end

  def test_default_prompt_order
    pending!("Default PromptManager ordering for chat completion")

    identifiers = TavernKit::SillyTavern::PromptManager.default_prompt_order
    assert_equal %w[
      main
      worldInfoBefore
      personaDescription
      charDescription
      charPersonality
      scenario
      enhanceDefinitions
      nsfw
      worldInfoAfter
      dialogueExamples
      chatHistory
      jailbreak
    ], identifiers
  end

  def test_continue_nudge_insertion
    pending!("continue_nudge appended after last chat message")

    prompt = TavernKit::SillyTavern::PromptBuilder.build(
      type: :continue,
      last_message: "Hello there"
    )

    assert_equal "continueNudge", prompt.last.identifier
  end

  def test_group_nudge_only_for_group
    pending!("group_nudge is inserted only for group chats and non-impersonate")

    prompt = TavernKit::SillyTavern::PromptBuilder.build(
      group: true,
      type: :normal
    )

    assert prompt.any? { |m| m.identifier == "groupNudge" }
  end
end
