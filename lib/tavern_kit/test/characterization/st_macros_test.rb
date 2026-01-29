# frozen_string_literal: true

require "test_helper"

class StMacrosTest < Minitest::Test
  def pending!(reason)
    skip("Pending ST parity (Wave 3 Macros): #{reason}")
  end

  def test_legacy_marker_rewrites
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = TavernKit::SillyTavern::Macro::Environment.new(
      user_name: "Alice",
      character_name: "Nyx",
      group_name: "Alice, Nyx",
    )
    result = engine.expand("<USER> meets <BOT> in <GROUP>", environment: env)
    assert_equal "Alice meets Nyx in Alice, Nyx", result
  end

  def test_time_utc_legacy_syntax
    pending!("Legacy time_UTC offset syntax")

    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    result = engine.expand("{{time_UTC-10}}", environment: TavernKit::SillyTavern::Macro::Environment.new)
    assert_match(/\A\d{2}:\d{2}\z/, result)
  end

  def test_if_else_scoped_macro
    pending!("Scoped if/else with preserveWhitespace flag")

    engine = TavernKit::SillyTavern::Macro::V2Engine.new

    template = "{{if .flag}}YES{{else}}NO{{/if}}"
    assert_equal "YES", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "true" }))
    assert_equal "NO", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "false" }))

    preserved = "{{#if .flag}}  YES  {{else}}  NO  {{/if}}"
    assert_equal "  YES  ", engine.expand(preserved, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "true" }))
  end

  def test_variable_shorthand_operators
    pending!("Variable shorthand (. / $) with +=, ??, || and comparisons")

    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    text = "{{.score+=1}}{{.score}}"
    assert_equal "1", engine.expand(text, environment: TavernKit::SillyTavern::Macro::Environment.new)
  end

  def test_trim_macro_postprocessing
    pending!("{{trim}} removes surrounding newlines after evaluation")

    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    template = "A\n{{trim}}\nB"
    assert_equal "AB", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new)
  end
end
