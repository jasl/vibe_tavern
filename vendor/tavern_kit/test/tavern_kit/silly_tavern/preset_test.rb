# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::PresetTest < Minitest::Test
  def test_with_returns_new_instance
    preset = TavernKit::SillyTavern::Preset.new(main_prompt: "A")
    other = preset.with(main_prompt: "B")

    refute_same preset, other
    assert_equal "A", preset.main_prompt
    assert_equal "B", other.main_prompt
  end

  def test_from_st_preset_json_builds_prompt_entries_and_coerces_continue_postfix
    preset = TavernKit::SillyTavern::Preset.from_st_preset_json(
      {
        "openai_max_context" => 4095,
        "openai_max_tokens" => 256,
        "continue_postfix" => 2,
        "temperature" => 0.7,
        "prompts" => [
          { "identifier" => "main", "name" => "Main Prompt", "role" => "system", "content" => "" },
          { "identifier" => "jailbreak", "name" => "PHI", "role" => "system", "content" => "PHI" },
          { "identifier" => "dialogueExamples", "name" => "Examples", "marker" => true },
          { "identifier" => "customThing", "name" => "Custom", "role" => "system", "content" => "X", "marker" => false },
          { "identifier" => "unknownMarker", "name" => "Unknown Marker", "marker" => true },
        ],
        "prompt_order" => [
          {
            "character_id" => 100_000,
            "order" => [
              { "identifier" => "main", "enabled" => true },
              { "identifier" => "unknownMarker", "enabled" => true },
              { "identifier" => "customThing", "enabled" => true },
            ],
          },
        ],
      },
    )

    assert_equal 4095, preset.context_window_tokens
    assert_equal 256, preset.reserved_response_tokens
    assert_equal "\n", preset.continue_postfix
    assert_in_delta 0.7, preset.temperature

    entries = preset.prompt_entries
    refute_nil entries

    main = entries.find { |e| e.id == "main_prompt" }
    assert main&.pinned?

    unknown_marker = entries.find { |e| e.id == "unknownMarker" }
    assert unknown_marker&.pinned?

    custom = entries.find { |e| e.id == "customThing" }
    assert custom
    refute custom.pinned?
  end

  def test_stopping_strings_ignores_invalid_custom_stopping_strings_json
    preset = TavernKit::SillyTavern::Preset.new(
      custom_stopping_strings: "not json",
      context_template: TavernKit::SillyTavern::ContextTemplate.new(
        names_as_stop_strings: false,
        use_stop_strings: false,
      ),
      instruct: TavernKit::SillyTavern::Instruct.new(enabled: false),
    )

    ctx = TavernKit::Prompt::Context.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob"),
    )

    assert_equal [], preset.stopping_strings(ctx)
  end

  def test_stopping_strings_assembles_all_sources
    preset = TavernKit::SillyTavern::Preset.new(
      single_line: true,
      custom_stopping_strings: "[\"X\", \"Y\"]",
      custom_stopping_strings_macro: true,
      instruct: TavernKit::SillyTavern::Instruct.new(
        enabled: true,
        stop_sequence: "STOP",
        sequences_as_stop_strings: false,
        macro: true,
        wrap: true,
      ),
      context_template: TavernKit::SillyTavern::ContextTemplate.new(
        names_as_stop_strings: true,
        use_stop_strings: true,
        chat_start: "CHAT_START",
        example_separator: "EX_SEP",
      ),
    )

    group = Struct.new(:members).new(
      [
        Struct.new(:name).new("Alice"), # excluded (same as char name)
        Struct.new(:name).new("Eve"),
      ],
    )

    ctx = TavernKit::Prompt::Context.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob"),
      generation_type: :continue,
      history: [{ role: :user, content: "hi" }],
      group: group,
      ephemeral_stopping_strings: ["EPHEMERAL"],
    )

    macro = ->(s) { s.gsub("CHAT_START", "CS").gsub("EX_SEP", "ES") }
    stops = preset.stopping_strings(ctx, macro_expander: macro)

    assert_equal "\n", stops.first

    # 1) names-based (continue + last message is user => includes char stop)
    assert_includes stops, "\nBob:"
    assert_includes stops, "\nAlice:"
    assert_includes stops, "\nEve:"

    # 2) instruct stop sequence (wrap=true)
    assert_includes stops, "\nSTOP"

    # 3) context markers
    assert_includes stops, "\nCS"
    assert_includes stops, "\nES"

    # 4) custom + ephemeral
    assert_includes stops, "X"
    assert_includes stops, "Y"
    assert_includes stops, "EPHEMERAL"
  end
end
