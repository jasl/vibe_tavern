# frozen_string_literal: true

require "test_helper"

class RisuaiCbsTest < Minitest::Test
  def render(text, **context)
    TavernKit::RisuAI::CBS.render(text, **context)
  end

  def pending!(reason)
    skip("Pending RisuAI parity: #{reason}")
  end

  def test_basic_escapes
    assert_equal "{{", render("{{bo}}")
    assert_equal "}}", render("{{bc}}")
    assert_equal "{", render("{{decbo}}")
    assert_equal "}", render("{{decbc}}")
    assert_equal "\n", render("{{br}}")
    assert_equal "\\n", render("{{cbr}}")

    assert_equal "abc", render("{{#pure}}  abc  {{/}}")
    assert_equal "\\{\\{x\\}\\}", render("{{#puredisplay}}{{x}}{{/}}")
    assert_equal "{x}", render("{{#escape}}{x}{{/}}")
    assert_equal "\n{x}\n", render("{{#escape::keep}}\n{x}\n{{/}}")
  end

  def test_if_and_when_blocks
    pending!("CBS #if/#when semantics and else handling")

    assert_equal "ok", render("{{#if 1}}ok{{/}}")
    assert_equal "", render("{{#if 0}}ok{{/}}")
    assert_equal "a", render("{{#when::1}}a{{:else}}b{{/}}")
    assert_equal "b", render("{{#when::0}}a{{:else}}b{{/}}")
    assert_equal "yes", render("{{#when::1::is::1}}yes{{/}}")
    assert_equal "", render("{{#when::1::is::2}}yes{{/}}")
  end

  def test_each_and_slot
    pending!("CBS #each + slot substitution")

    assert_equal "a::b::c", render("{{#each [a,b,c] as item}}{{slot::item}}::{{/}}")
    assert_equal "1-2-3", render("{{#each [1,2,3] as n}}{{slot::n}}-{{/}}").chomp("-")
  end

  def test_function_and_call
    pending!("CBS #func and call:: expansion")

    input = "{{#func greet who}}Hello {{arg::1}}{{/}}{{call::greet::world}}"
    assert_equal "Hello world", render(input)
  end

  def test_calc_expression
    pending!("CBS ? expression with operators and vars")

    assert_equal "7", render("{{? 1 + 2 * 3}}")
    assert_equal "1", render("{{? 3 > 2}}")
    assert_equal "0", render("{{? 3 < 2}}")
  end
end
