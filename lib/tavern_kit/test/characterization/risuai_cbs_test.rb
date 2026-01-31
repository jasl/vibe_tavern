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
    assert_equal "a::b::c", render("{{#each [\"a\",\"b\",\"c\"] as item}}{{slot::item}}::{{/}}").chomp("::")
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

  def test_variable_macros_and_return
    store = TavernKit::ChatVariables::InMemory.new

    # Upstream: setvar/addvar/setdefaultvar only run when runVar=true.
    assert_equal "{{setvar::flag::1}}", render("{{setvar::flag::1}}", variables: store)
    assert_nil store.get("flag", scope: :local)

    assert_equal "", render("{{setvar::flag::1}}", variables: store, run_var: true)
    assert_equal "1", store.get("flag", scope: :local)
    assert_equal "1", render("{{getvar::flag}}", variables: store)

    assert_equal "", render("{{addvar::flag::2}}", variables: store, run_var: true)
    assert_equal "3", store.get("flag", scope: :local)

    assert_equal "", render("{{setdefaultvar::flag::999}}", variables: store, run_var: true)
    assert_equal "3", store.get("flag", scope: :local)

    store.set("g", "ok", scope: :global)
    assert_equal "ok", render("{{getglobalvar::g}}", variables: store)
    assert_equal "1", render("{{getglobalvar::toggle_x}}", toggles: { x: "1" })

    assert_equal "1", render("{{settempvar::x::1}}{{tempvar::x}}")

    assert_equal "b", render("a{{return::b}}c")

    input = "{{#func f}}{{settempvar::x::1}}{{return::{{tempvar::x}}}}IGNORED{{/}}{{call::f}}|{{tempvar::x}}"
    assert_equal "1|", render(input)

    # rmVar: removes setter macros without mutating variables (used for stripping).
    store2 = TavernKit::ChatVariables::InMemory.new
    assert_equal "", render("{{setvar::flag::1}}", variables: store2, run_var: true, rm_var: true)
    assert_nil store2.get("flag", scope: :local)
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

  def test_string_and_number_helpers
    assert_equal "1", render("{{startswith::Hello World::Hello}}")
    assert_equal "0", render("{{startswith::Hello World::World}}")
    assert_equal "1", render("{{endswith::Hello World::World}}")
    assert_equal "0", render("{{endswith::Hello World::Hello}}")
    assert_equal "1", render("{{contains::Hello World::lo Wo}}")
    assert_equal "0", render("{{contains::Hello World::x}}")

    assert_equal "Hell0 W0rld", render("{{replace::Hello World::o::0}}")
    assert_equal "[\"apple\",\"banana\",\"cherry\"]", render("{{split::apple,banana,cherry::,}}")
    assert_equal "apple, banana", render("{{join::[\"apple\",\"banana\"]::, }}")
    assert_equal "a::b::c", render("{{spread::[\"a\",\"b\",\"c\"]}}")
    assert_equal "3", render("{{arraylength::[\"a\",\"b\",\"c\"]}}")
    assert_equal "3", render("{{arraylength::a\u00A7b\u00A7c}}")
    assert_equal "123.45", render("{{tonumber::abc123.45def}}")
    assert_equal "8", render("{{pow::2::3}}")
    assert_equal "b", render("{{arrayelement::[\"a\",\"b\",\"c\"]::1}}")
    assert_equal "null", render("{{arrayelement::[\"a\",\"b\",\"c\"]::99}}")
    assert_equal "hello world", render("{{trim::  hello world  }}")
    assert_equal "5", render("{{length::Hello}}")
    assert_equal "hello world", render("{{lower::Hello WORLD}}")
    assert_equal "HELLO WORLD", render("{{upper::Hello world}}")
    assert_equal "Hello world", render("{{capitalize::hello world}}")

    assert_equal "4", render("{{round::3.7}}")
    assert_equal "-1", render("{{round::-1.5}}") # JS: Math.round(-1.5) => -1
    assert_equal "3", render("{{floor::3.9}}")
    assert_equal "4", render("{{ceil::3.1}}")
    assert_equal "5", render("{{abs::-5}}")
    assert_equal "1", render("{{remaind::10::3}}")
  end

  def test_deterministic_rng_and_metadata_macros
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (hash/pick/rollp/chatindex/model/role)
    # resources/Risuai/src/ts/util.ts (pickHashRand)

    expected_hash = ((TavernKit::RisuAI::Utils.pick_hash_rand(0, "hello") * 10_000_000) + 1).round.to_i.to_s.rjust(7, "0")
    assert_equal expected_hash, render("{{hash::hello}}")

    cid = 42
    seed = "seed-word"
    rand = TavernKit::RisuAI::Utils.pick_hash_rand(cid, seed)

    assert_equal rand.to_s, render("{{pick}}", message_index: cid, rng_word: seed)

    list = %w[a b c]
    assert_equal list[(rand * list.length).floor], render("{{pick::a,b,c}}", message_index: cid, rng_word: seed)
    assert_equal list[(rand * 2).floor], render("{{pick::[\"a\",\"b\"]}}", message_index: cid, rng_word: seed)
    assert_equal "a,b", render("{{pick::a\\,b,c}}", message_index: cid, rng_word: seed)

    sides = 6
    expected_total = (0...2).sum do |i|
      ((TavernKit::RisuAI::Utils.pick_hash_rand(cid + (i * 15), seed) * sides).floor + 1)
    end
    assert_equal expected_total.to_s, render("{{rollp::2d6}}", message_index: cid, rng_word: seed)
    assert_equal expected_total.to_s, render("{{rollpick::2d6}}", message_index: cid, rng_word: seed)

    expected_d20 = ((TavernKit::RisuAI::Utils.pick_hash_rand(cid, seed) * 20).floor + 1).to_s
    assert_equal expected_d20, render("{{rollp::20}}", message_index: cid, rng_word: seed)

    assert_equal "1", render("{{rollp}}")
    assert_equal "NaN", render("{{rollp::0d6}}")
    assert_equal "NaN", render("{{rollp::2d0}}")
    assert_equal "NaN", render("{{rollp::abc}}")

    assert_equal "-1", render("{{chatindex}}", chat_index: -1)
    assert_equal "9", render("{{chat_index}}", chat_index: 9)
    assert_equal "42", render("{{message_index}}", message_index: 42)
    assert_equal "gpt-4o", render("{{model}}", model_hint: "gpt-4o")
    assert_equal "assistant", render("{{role}}", role: :assistant)
  end

  def test_nondeterministic_rng_macros
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (random/randint/dice/roll)

    v = Float(render("{{random}}"))
    assert_operator v, :>=, 0
    assert_operator v, :<, 1

    # Deterministic assertion: all candidates are identical.
    assert_equal "a", render("{{random::a,a,a}}")

    randint = Integer(render("{{randint::1::10}}"))
    assert_operator randint, :>=, 1
    assert_operator randint, :<=, 10
    assert_equal "NaN", render("{{randint::a::10}}")

    dice = Integer(render("{{dice::2d6}}"))
    assert_operator dice, :>=, 2
    assert_operator dice, :<=, 12
    assert_equal "NaN", render("{{dice::ad6}}")

    roll = Integer(render("{{roll::2d6}}"))
    assert_operator roll, :>=, 2
    assert_operator roll, :<=, 12

    d20 = Integer(render("{{roll::20}}"))
    assert_operator d20, :>=, 1
    assert_operator d20, :<=, 20

    assert_equal "1", render("{{roll}}")
    assert_equal "NaN", render("{{roll::0d6}}")
    assert_equal "NaN", render("{{roll::2d0}}")
    assert_equal "NaN", render("{{roll::abc}}")
  end
end
