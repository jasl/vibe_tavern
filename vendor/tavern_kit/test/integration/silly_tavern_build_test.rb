# frozen_string_literal: true

require "test_helper"

class SillyTavernBuildTest < Minitest::Test
  def test_build_runs_end_to_end_and_produces_a_plan
    character =
      TavernKit::Character.create(
        name: "Nyx",
        description: "A mysterious guide.",
        personality: "Calm.",
        scenario: "A quiet library.",
        first_mes: "Hello.",
        mes_example: "<START>\n{{user}}: Hi\n{{char}}: Hello\n",
        post_history_instructions: "Stay in character.",
      )

    user = TavernKit::User.new(name: "Alice", persona: "A curious visitor.")

    preset =
      TavernKit::SillyTavern::Preset.new(
        main_prompt: "MAIN",
        post_history_instructions: "PHI",
      )

    plan =
      TavernKit::SillyTavern.build do
        character character
        user user
        preset preset
        history []
        message "Hello!"
        dialect :openai
      end

    assert_instance_of TavernKit::Prompt::Plan, plan
    assert plan.enabled_blocks.any?
    assert plan.enabled_blocks.any? { |b| b.content.include?("Hello!") }
  end

  def test_to_messages_openai_runs_end_to_end
    character = TavernKit::Character.create(name: "Nyx", description: "D", personality: "P", scenario: "S")
    user = TavernKit::User.new(name: "Alice")

    messages =
      TavernKit::SillyTavern.to_messages(dialect: :openai) do
        character character
        user user
        message "Hello!"
      end

    assert messages.any?, "expected non-empty messages"
    assert messages.any? { |m| m[:role] == "user" && m[:content] == "Hello!" }
  end

  def test_instruct_and_context_template_macros_expand_from_preset
    character = TavernKit::Character.create(name: "Nyx")
    user = TavernKit::User.new(name: "Alice")

    preset =
      TavernKit::SillyTavern::Preset.new(
        main_prompt: "A {{chatStart}} {{instructInput}} B",
        use_sysprompt: true,
        instruct: TavernKit::SillyTavern::Instruct.new(enabled: true, input_sequence: "IN"),
        context_template: TavernKit::SillyTavern::ContextTemplate.new(chat_start: "<CHAT>"),
      )

    plan =
      TavernKit::SillyTavern.build do
        character character
        user user
        preset preset
        history []
        message "Hello!"
        dialect :openai
      end

    main = plan.enabled_blocks.find { |b| b.slot == :main_prompt }
    assert main, "expected a main_prompt block"
    assert_equal "A <CHAT> IN B", main.content
  end
end
