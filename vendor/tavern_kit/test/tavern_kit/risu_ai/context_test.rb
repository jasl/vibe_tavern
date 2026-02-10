# frozen_string_literal: true

require "test_helper"

class TavernKit::RisuAI::ContextTest < Minitest::Test
  def test_normalize_coerces_known_fields
    char = TavernKit::Character.create(name: "Seraphina")
    ctx = TavernKit::PromptBuilder::Context.new(character: char, history: [])

    risu_context = TavernKit::RisuAI::Context.build(
      {
        "chatIndex" => "5",
        "messageIndex" => 42,
        "rngWord" => "seed",
        "runVar" => "0",
        "rmVar" => "1",
        "cbsConditions" => { "chatRole" => "user", "firstmsg" => true },
        "toggles" => { "x" => "1" },
        "metadata" => { "ModelName" => "gpt-4o", "model_short_name" => "4o" },
        "modules" => %w[a b],
      },
      context: ctx,
      strict: true,
    )

    h = risu_context.to_h
    assert_equal 5, h[:chat_index]
    assert_equal 42, h[:message_index]
    assert_equal "seed", h[:rng_word]
    assert_equal false, h[:run_var]
    assert_equal true, h[:rm_var]

    # cbsConditions keys are normalized to the macro key form.
    assert_equal "user", h[:cbs_conditions]["chatrole"]
    assert_equal true, h[:cbs_conditions]["firstmsg"]

    assert_equal({ "x" => "1" }, h[:toggles])

    # Metadata keys are normalized to the macro key form.
    assert_equal "gpt-4o", h[:metadata]["modelname"]
    assert_equal "4o", h[:metadata]["modelshortname"]

    assert_equal %w[a b], h[:modules]
  end

  def test_rng_word_default_falls_back_to_character_name
    char = TavernKit::Character.create(name: "Seraphina")
    ctx = TavernKit::PromptBuilder::Context.new(character: char, history: [])

    risu_context = TavernKit::RisuAI::Context.build({}, context: ctx)
    assert_equal "Seraphina", risu_context.to_h[:rng_word]
  end
end
