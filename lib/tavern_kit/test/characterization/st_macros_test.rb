# frozen_string_literal: true

require "test_helper"

class StMacrosTest < Minitest::Test
  def pending!(reason)
    skip("Pending ST parity: #{reason}")
  end

  def test_legacy_marker_rewrites
    pending!("Macro pre-processor rewrites legacy <USER>/<BOT>/<GROUP> markers")

    result = TavernKit::SillyTavern::Macros.render("<USER> meets <BOT> in <GROUP>")
    assert_equal "Alice meets Nyx in Alice, Nyx", result
  end

  def test_time_utc_legacy_syntax
    pending!("Legacy time_UTC offset syntax")

    result = TavernKit::SillyTavern::Macros.render("{{time_UTC-10}}")
    assert_match(/\A\d{2}:\d{2}\z/, result)
  end

  def test_if_else_scoped_macro
    pending!("Scoped if/else with preserveWhitespace flag")

    template = "{{#if .flag}}YES{{else}}NO{{/if}}"
    assert_equal "YES", TavernKit::SillyTavern::Macros.render(template, locals: { "flag" => "true" })
    assert_equal "NO", TavernKit::SillyTavern::Macros.render(template, locals: { "flag" => "false" })

    preserved = "{{#if .flag}}  YES  {{else}}  NO  {{/if}}"
    assert_equal "  YES  ", TavernKit::SillyTavern::Macros.render(preserved, locals: { "flag" => "true" })
  end

  def test_variable_shorthand_operators
    pending!("Variable shorthand (. / $) with +=, ??, || and comparisons")

    text = "{{.score+=1}}{{.score}}"
    assert_equal "1", TavernKit::SillyTavern::Macros.render(text, locals: {})
  end

  def test_trim_macro_postprocessing
    pending!("{{trim}} removes surrounding newlines after evaluation")

    template = "A\n{{trim}}\nB"
    assert_equal "AB", TavernKit::SillyTavern::Macros.render(template)
  end
end
