# frozen_string_literal: true

require "test_helper"

class StPromptManagerTest < Minitest::Test
  def test_default_prompt_order
    preset = TavernKit::SillyTavern::Preset.new(prefer_char_prompt: false)
    char = TavernKit::Character.create(
      name: "Alice",
      description: "DESC",
      personality: "PERS",
      scenario: "SCEN",
      mes_example: "<START>\nExample 1",
    )

    plan = TavernKit::SillyTavern.build do
      dialect :openai
      character char
      user TavernKit::User.new(name: "Bob", persona: "Persona")
      preset preset
      history [{ role: :assistant, content: "A1" }]
      message "U1"
    end

    slots = plan.blocks.map(&:slot).compact.uniq

    assert_equal(
      [
        :main_prompt,
        :persona_description,
        :character_description,
        :character_personality,
        :scenario,
        :chat_examples,
        :chat_history,
      ],
      slots,
    )
  end

  def test_continue_nudge_insertion
    preset = TavernKit::SillyTavern::Preset.new(
      prefer_char_prompt: false,
      continue_prefill: false,
      continue_nudge_prompt: "NUDGE {{char}}",
    )

    plan = TavernKit::SillyTavern.build do
      dialect :openai
      generation_type :continue

      character TavernKit::Character.create(name: "Alice")
      user TavernKit::User.new(name: "Bob", persona: "Persona")
      preset preset

      history [{ role: :assistant, content: "A1" }]
      message ""
    end

    assert_equal :continue_nudge_prompt, plan.blocks.last.slot
    assert_equal "NUDGE Alice", plan.blocks.last.content
  end

  def test_group_nudge_only_for_group
    preset = TavernKit::SillyTavern::Preset.new(prefer_char_prompt: false, group_nudge_prompt: "GROUP {{char}}")

    plan = TavernKit::SillyTavern.build do
      dialect :openai
      generation_type :normal

      character TavernKit::Character.create(name: "Alice")
      user TavernKit::User.new(name: "Bob", persona: "Persona")
      preset preset

      group({ any: "value" })
      history []
      message "hi"
    end

    assert plan.blocks.any? { |b| b.slot == :group_nudge_prompt }

    plan = TavernKit::SillyTavern.build do
      dialect :openai
      generation_type :impersonate

      character TavernKit::Character.create(name: "Alice")
      user TavernKit::User.new(name: "Bob", persona: "Persona")
      preset preset

      group({ any: "value" })
      history []
      message "hi"
    end

    refute plan.blocks.any? { |b| b.slot == :group_nudge_prompt }
  end
end
