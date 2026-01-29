# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Preset::StImporterTest < Minitest::Test
  def test_imports_all_prompt_affecting_fields
    preset = TavernKit::SillyTavern::Preset.from_st_preset_json(
      {
        # Budgets
        "openai_max_context" => "9001",
        "openai_max_tokens" => -5,
        "message_token_overhead" => -10,
        "max_context_unlocked" => "1",

        # Sampling
        "temperature" => 0.7,
        "temp_openai" => 1.3,
        "top_p" => 0.9,
        "top_p_openai" => 0.2,
        "top_k" => "4",
        "top_a" => "0.25",
        "min_p" => "0.125",
        "frequency_penalty" => "0.5",
        "presence_penalty" => "0.25",
        "repetition_penalty" => "1.15",

        # Prompt management flags
        "use_sysprompt" => "true",
        "squash_system_messages" => "false",
        "names_behavior" => 2,
        "custom_prompt_post_processing" => "",
        "bias_preset_selected" => "Default (none)",

        # Templates
        "send_if_empty" => "SEND",
        "new_chat_prompt" => "NEW_CHAT",
        "new_group_chat_prompt" => "NEW_GROUP_CHAT",
        "new_example_chat_prompt" => "NEW_EXAMPLE",
        "continue_nudge_prompt" => "CONTINUE_NUDGE",
        "group_nudge_prompt" => "GROUP_NUDGE",
        "impersonation_prompt" => "IMPERSONATE",
        "assistant_prefill" => "PREFILL",
        "assistant_impersonation" => "IMP",

        # Continue
        "continue_prefill" => true,
        "continue_postfix" => "3",

        # World Info defaults
        "world_info_depth" => "-1",
        "world_info_budget" => "2048",
        "world_info_budget_cap" => "-100",
        "world_info_include_names" => "0",
        "world_info_min_activations" => "-1",
        "world_info_min_activations_depth_max" => "10",
        "world_info_use_group_scoring" => "yes",

        # Author's Note defaults
        "authors_note" => "AN",
        "authors_note_frequency" => -1,
        "authors_note_position" => "before_prompt",
        "authors_note_depth" => -2,
        "authors_note_role" => "2",
        "allowWIScan" => "on",

        # Format templates
        "wi_format" => "WI({0})",
        "scenario_format" => "SC({{scenario}})",
        "personality_format" => "PE({{personality}})",

        # Misc behaviors
        "examples_behavior" => "always_keep",
        "prefer_character_prompt" => false,
        "prefer_character_jailbreak" => false,
        "character_lore_insertion_strategy" => "sorted_evenly",

        # Stop strings
        "custom_stopping_strings" => "[\"A\",\"B\"]",
        "custom_stopping_strings_macro" => false,
        "single_line" => true,

        # Instruct / Context sub-presets
        "instruct" => {
          "name" => "MyInstruct",
          "enabled" => true,
          "input_sequence" => "IN {{name}}",
          "output_sequence" => "OUT {{name}}",
          "system_sequence" => "SYS {{name}}",
          "stop_sequence" => "STOP",
          "wrap" => false,
          "macro" => false,
          "names_behavior" => "always",
          "sequences_as_stop_strings" => true,
          "skip_examples" => true,
        },
        "context" => {
          "name" => "MyContext",
          "story_string" => "{{#if system}}{{system}}{{/if}}{{trim}}",
          "chat_start" => "<CHAT_START>",
          "example_separator" => "<EX_SEP>",
          "use_stop_strings" => false,
          "names_as_stop_strings" => false,
          "story_string_position" => 1,
          "story_string_depth" => 5,
          "story_string_role" => 2,
        },

        # Prompt Manager (prompts + order)
        "prompts" => [
          { "identifier" => "main", "name" => "Main Prompt", "role" => 0, "content" => "" },
          { "identifier" => "jailbreak", "name" => "PHI", "role" => "system", "content" => "PHI" },
          { "identifier" => "nsfw", "name" => "Aux", "role" => "system", "content" => "AUX" },
          { "identifier" => "enhanceDefinitions", "name" => "Enhance", "role" => "system", "content" => "" },
          { "identifier" => "unknownMarker", "name" => "Unknown Marker", "marker" => true },
          { "identifier" => "customThing", "name" => "Custom", "role" => 1, "content" => "CUSTOM", "marker" => false },
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

    # Main prompt comes from prompts[] but falls back when blank.
    assert_equal TavernKit::SillyTavern::Preset::DEFAULT_MAIN_PROMPT, preset.main_prompt
    assert_equal "PHI", preset.post_history_instructions
    assert_equal TavernKit::SillyTavern::Preset::DEFAULT_ENHANCE_DEFINITIONS, preset.enhance_definitions
    assert_equal "AUX", preset.auxiliary_prompt

    assert_equal 9001, preset.context_window_tokens
    assert_equal 0, preset.reserved_response_tokens
    assert_equal 0, preset.message_token_overhead
    assert_equal true, preset.max_context_unlocked

    assert_in_delta 0.7, preset.temperature
    assert_in_delta 0.9, preset.top_p
    assert_equal 4, preset.top_k
    assert_in_delta 0.25, preset.top_a
    assert_in_delta 0.125, preset.min_p
    assert_in_delta 0.5, preset.frequency_penalty
    assert_in_delta 0.25, preset.presence_penalty
    assert_in_delta 1.15, preset.repetition_penalty

    assert_equal true, preset.use_sysprompt
    assert_equal false, preset.squash_system_messages
    assert_equal :content, preset.names_behavior
    assert_nil preset.custom_prompt_post_processing
    assert_equal "Default (none)", preset.bias_preset_selected

    assert_equal "SEND", preset.send_if_empty
    assert_equal "NEW_CHAT", preset.new_chat_prompt
    assert_equal "NEW_GROUP_CHAT", preset.new_group_chat_prompt
    assert_equal "NEW_EXAMPLE", preset.new_example_chat_prompt
    assert_equal "CONTINUE_NUDGE", preset.continue_nudge_prompt
    assert_equal "GROUP_NUDGE", preset.group_nudge_prompt
    assert_equal "IMPERSONATE", preset.impersonation_prompt
    assert_equal "PREFILL", preset.assistant_prefill
    assert_equal "IMP", preset.assistant_impersonation

    assert_equal true, preset.continue_prefill
    assert_equal "\n\n", preset.continue_postfix

    assert_equal 0, preset.world_info_depth
    assert_equal 2048, preset.world_info_budget
    assert_equal 0, preset.world_info_budget_cap
    assert_equal false, preset.world_info_include_names
    assert_equal 0, preset.world_info_min_activations
    assert_equal 10, preset.world_info_min_activations_depth_max
    assert_equal true, preset.world_info_use_group_scoring

    assert_equal "AN", preset.authors_note
    assert_equal 0, preset.authors_note_frequency
    assert_equal :before_prompt, preset.authors_note_position
    assert_equal 0, preset.authors_note_depth
    assert_equal :assistant, preset.authors_note_role
    assert_equal true, preset.authors_note_allow_wi_scan

    assert_equal "WI({0})", preset.wi_format
    assert_equal "SC({{scenario}})", preset.scenario_format
    assert_equal "PE({{personality}})", preset.personality_format

    assert_equal :always_keep, preset.examples_behavior
    assert_equal false, preset.prefer_char_prompt
    assert_equal false, preset.prefer_char_instructions
    assert_equal :sorted_evenly, preset.character_lore_insertion_strategy

    assert_equal "[\"A\",\"B\"]", preset.custom_stopping_strings
    assert_equal false, preset.custom_stopping_strings_macro
    assert_equal true, preset.single_line

    assert_instance_of TavernKit::SillyTavern::Instruct, preset.instruct
    assert_equal "MyInstruct", preset.instruct.preset
    assert_equal true, preset.instruct.enabled?
    assert_equal false, preset.instruct.wrap?
    assert_equal false, preset.instruct.macro?
    assert_equal :always, preset.instruct.names_behavior
    assert_equal true, preset.instruct.sequences_as_stop_strings?
    assert_equal true, preset.instruct.skip_examples?

    assert_instance_of TavernKit::SillyTavern::ContextTemplate, preset.context_template
    assert_equal "MyContext", preset.context_template.preset
    assert_equal false, preset.context_template.use_stop_strings?
    assert_equal false, preset.context_template.names_as_stop_strings?
    assert_equal :in_chat, preset.context_template.story_string_position
    assert_equal 5, preset.context_template.story_string_depth
    assert_equal :assistant, preset.context_template.story_string_role

    assert_instance_of Array, preset.prompt_entries
    assert_equal %w[main_prompt unknownMarker customThing], preset.prompt_entries.map(&:id)

    unknown_marker = preset.prompt_entries.find { |e| e.id == "unknownMarker" }
    assert unknown_marker&.pinned?

    custom = preset.prompt_entries.find { |e| e.id == "customThing" }
    refute custom.pinned?
    assert_equal :user, custom.role
  end

  def test_prompt_order_flat_array_is_supported
    preset = TavernKit::SillyTavern::Preset.from_st_preset_json(
      {
        "prompts" => [
          { "identifier" => "main", "content" => "M", "role" => "system" },
          { "identifier" => "jailbreak", "content" => "J", "role" => "system" },
        ],
        "prompt_order" => [
          { "identifier" => "jailbreak", "enabled" => true },
          { "identifier" => "main", "enabled" => false },
        ],
      },
    )

    assert_equal %w[post_history_instructions main_prompt], preset.prompt_entries.map(&:id)
    assert_equal [true, false], preset.prompt_entries.map(&:enabled?)
  end
end
