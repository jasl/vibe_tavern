# frozen_string_literal: true

require "test_helper"

class TestTavernKit < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::TavernKit::VERSION
  end

  def test_load_preset_nil_returns_default_st_preset
    preset = TavernKit.load_preset(nil)
    assert_instance_of TavernKit::SillyTavern::Preset, preset
  end

  def test_load_preset_from_keyword_hash
    preset = TavernKit.load_preset(
      main_prompt: "Hello",
      context_window_tokens: 123,
      reserved_response_tokens: 7,
    )

    assert_equal "Hello", preset.main_prompt
    assert_equal 123, preset.context_window_tokens
    assert_equal 7, preset.reserved_response_tokens
  end

  def test_load_preset_from_st_json_shape
    preset = TavernKit.load_preset(
      {
        "prompts" => [
          { "identifier" => "main", "content" => "Main prompt" },
        ],
        "openai_max_context" => 500,
        "openai_max_tokens" => 50,
      },
    )

    assert_equal "Main prompt", preset.main_prompt
    assert_equal 500, preset.context_window_tokens
    assert_equal 50, preset.reserved_response_tokens
  end

  def test_pipeline_returns_st_pipeline
    assert_equal TavernKit::SillyTavern::Pipeline, TavernKit.pipeline
  end
end
