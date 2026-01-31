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
    assert_equal "abc", render("{{#pure}}abc{{/pure}}")
    assert_equal "\\{\\{x\\}\\}", render("{{#puredisplay}}{{x}}{{/}}")
    assert_equal "\u{E9B8}x\u{E9B9}", render("{{#escape}}{x}{{/}}")
    assert_equal "\n\u{E9B8}x\u{E9B9}\n", render("{{#escape::keep}}\n{x}\n{{/}}")

    assert_equal "ab", render("a{{// comment}}b")
    assert_equal "\n", render("{{#code}}\\n{{/}}")
    assert_equal "A", render("{{#code}}\\u0041{{/}}")
  end

  def test_if_and_when_blocks
    assert_equal "ok", render("{{#if 1}}ok{{/}}")
    assert_equal "", render("{{#if 0}}ok{{/}}")
    assert_equal "ok", render("{{#if TRUE}}ok{{/}}")
    assert_equal "ok", render("{{#if 1}}ok{{/if}}")
    assert_equal "a", render("{{#when::1}}a{{:else}}b{{/}}")
    assert_equal "b", render("{{#when::0}}a{{:else}}b{{/}}")
    assert_equal "yes", render("{{#when::1::is::1}}yes{{/}}")
    assert_equal "", render("{{#when::1::is::2}}yes{{/}}")
    assert_equal "yes", render("{{#when::1}}yes{{/when}}")
  end

  def test_each_and_slot
    assert_equal "a::b::c", render("{{#each [a,b,c] as item}}{{slot::item}}::{{/}}").chomp("::")
    assert_equal "1-2-3", render("{{#each [1,2,3] as n}}{{slot::n}}-{{/}}").chomp("-")
  end

  def test_function_and_call
    input = "{{#func greet who}}Hello {{arg::1}}{{/}}{{call::greet::world}}"
    assert_equal "Hello world", render(input)
  end

  def test_basic_macros
    char = TavernKit::Character.create(name: "Seraphina")
    user = TavernKit::User.new(name: "Alice", persona: "A curious adventurer")

    assert_equal "Seraphina", render("{{char}}", character: char, user: user)
    assert_equal "Seraphina", render("{{bot}}", character: char, user: user)
    assert_equal "Alice", render("{{user}}", character: char, user: user)

    assert_equal "1", render("{{prefill_supported}}", dialect: :anthropic)
    assert_equal "0", render("{{prefill_supported}}", dialect: :openai)
    assert_equal "1", render("{{prefill_supported}}", model_hint: "claude-3-haiku-20240307")

    assert_equal "ok", render("{{#if {{prefill_supported}}}}ok{{/}}", dialect: :anthropic)
    assert_equal "", render("{{#if {{prefill_supported}}}}ok{{/}}", dialect: :openai)

    assert_equal "yes", render("{{#when::toggle::x}}yes{{/}}", toggles: { x: "1" })
    assert_equal "", render("{{#when::toggle::x}}yes{{/}}", toggles: { x: "0" })
  end

  def test_calc_expression_with_variables
    store = TavernKit::ChatVariables::InMemory.new
    store.set("x", 2, scope: :local)
    store.set("y", 3, scope: :global)

    assert_equal "5", render("{{? $x + @y}}", variables: store)
  end

  def test_call_stack_limit
    input = "{{#func loop}}{{call::loop}}{{/}}{{call::loop}}"
    assert_equal "ERROR: Call stack limit reached", render(input)
  end

  def test_calc_expression
    assert_equal "7", render("{{? 1 + 2 * 3}}")
    assert_equal "1", render("{{? 3 > 2}}")
    assert_equal "0", render("{{? 3 < 2}}")
  end
end
