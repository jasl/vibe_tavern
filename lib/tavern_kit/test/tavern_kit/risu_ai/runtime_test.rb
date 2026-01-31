# frozen_string_literal: true

require "test_helper"

class TavernKit::RisuAI::RuntimeTest < Minitest::Test
  def test_normalize_coerces_known_fields
    char = TavernKit::Character.create(name: "Seraphina")
    ctx = TavernKit::Prompt::Context.new(character: char, history: [])

    runtime = TavernKit::RisuAI::Runtime.build(
      {
        "chatIndex" => "5",
        "messageIndex" => 42,
        "rngWord" => "seed",
        "runVar" => "0",
        "rmVar" => "1",
        "toggles" => { "x" => "1" },
        "metadata" => { "ModelName" => "gpt-4o", "model_short_name" => "4o" },
        "modules" => %w[a b],
      },
      context: ctx,
      strict: true,
    )

    h = runtime.to_h
    assert_equal 5, h[:chat_index]
    assert_equal 42, h[:message_index]
    assert_equal "seed", h[:rng_word]
    assert_equal false, h[:run_var]
    assert_equal true, h[:rm_var]
    assert_equal({ "x" => "1" }, h[:toggles])

    # Metadata keys are normalized to the macro key form.
    assert_equal "gpt-4o", h[:metadata]["modelname"]
    assert_equal "4o", h[:metadata]["modelshortname"]

    assert_equal %w[a b], h[:modules]
  end

  def test_rng_word_default_falls_back_to_character_name
    char = TavernKit::Character.create(name: "Seraphina")
    ctx = TavernKit::Prompt::Context.new(character: char, history: [])

    runtime = TavernKit::RisuAI::Runtime.build({}, context: ctx)
    assert_equal "Seraphina", runtime.to_h[:rng_word]
  end
end
