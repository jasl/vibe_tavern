# frozen_string_literal: true

require "test_helper"
require "base64"

class RisuaiCbsTest < Minitest::Test
  def render(text, **context)
    TavernKit::RisuAI::CBS.render(text, **context)
  end

  def pending!(reason)
    skip("Pending RisuAI parity: #{reason}")
  end

  def test_basic_escapes
    assert_equal "\u{E9B8}\u{E9B8}", render("{{bo}}")
    assert_equal "\u{E9B9}\u{E9B9}", render("{{bc}}")
    assert_equal "\u{E9B8}", render("{{decbo}}")
    assert_equal "\u{E9B9}", render("{{decbc}}")
    assert_equal "\n", render("{{br}}")
    assert_equal "\\n", render("{{cbr}}")
    assert_equal "\n", render("{{newline}}")
    assert_equal "\\n\\n\\n", render("{{cbr::3}}")

    assert_equal "\u{E9BA}", render("{{displayescapedbracketopen}}")
    assert_equal "\u{E9BB}", render("{{displayescapedbracketclose}}")
    assert_equal "\u{E9BC}", render("{{displayescapedanglebracketopen}}")
    assert_equal "\u{E9BD}", render("{{displayescapedanglebracketclose}}")
    assert_equal "\u{E9BE}", render("{{displayescapedcolon}}")
    assert_equal "\u{E9BF}", render("{{displayescapedsemicolon}}")

    assert_equal "\u{E9BA}", render("{{debo}}")
    assert_equal "\u{E9BB}", render("{{debc}}")
    assert_equal "\u{E9BC}", render("{{deabo}}")
    assert_equal "\u{E9BD}", render("{{deabc}}")
    assert_equal "\u{E9BE}", render("{{dec}}")
    assert_equal "\u{E9BF}", render("{{;}}")

    assert_equal "\u{E9BA}", render("{{(}}")
    assert_equal "\u{E9BB}", render("{{)}}")
    assert_equal "\u{E9BC}", render("{{<}}")
    assert_equal "\u{E9BD}", render("{{>}}")

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

  def test_cbs_conditions_affect_role_and_first_message_macros
    assert_equal "user", render("{{role}}", cbs_conditions: { chatRole: "user" })
    assert_equal "char", render("{{role}}", cbs_conditions: { firstmsg: true })

    assert_equal "1", render("{{isfirstmsg}}", cbs_conditions: { firstmsg: true })
    assert_equal "0", render("{{isfirstmsg}}", cbs_conditions: { firstmsg: false })
  end

  def test_character_field_macros_expand_inner_cbs
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (personality/description/scenario/exampledialogue/persona)

    char = TavernKit::Character.create(
      name: "Seraphina",
      personality: "P={{user}}",
      description: "D={{char}}",
      scenario: "S={{user}}&{{char}}",
      mes_example: "E={{user}}",
    )
    user = TavernKit::User.new(name: "Alice", persona: "I am {{user}}")

    assert_equal "P=Alice", render("{{personality}}", character: char, user: user)
    assert_equal "P=Alice", render("{{charpersona}}", character: char, user: user)
    assert_equal "D=Seraphina", render("{{description}}", character: char, user: user)
    assert_equal "D=Seraphina", render("{{chardesc}}", character: char, user: user)
    assert_equal "S=Alice&Seraphina", render("{{scenario}}", character: char, user: user)
    assert_equal "E=Alice", render("{{exampledialogue}}", character: char, user: user)
    assert_equal "E=Alice", render("{{examplemessage}}", character: char, user: user)
    assert_equal "I am Alice", render("{{persona}}", character: char, user: user)
    assert_equal "I am Alice", render("{{userpersona}}", character: char, user: user)
  end

  def test_calc_expression_with_variables
    store = TavernKit::Store::InMemory.new
    store.set("x", 2, scope: :local)
    store.set("y", 3, scope: :global)

    assert_equal "5", render("{{? $x + @y}}", variables: store)
  end

  def test_variable_macros_and_return
    store = TavernKit::Store::InMemory.new

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
    store2 = TavernKit::Store::InMemory.new
    assert_equal "", render("{{setvar::flag::1}}", variables: store2, run_var: true, rm_var: true)
    assert_nil store2.get("flag", scope: :local)
  end

  def test_missing_store_variables_return_null_and_match_upstream_edge_cases
    # Upstream reference:
    # resources/Risuai/src/ts/parser/chatVar.svelte.ts (getChatVar/getGlobalChatVar)
    # resources/Risuai/src/ts/cbs.ts (setdefaultvar/addvar)

    store = TavernKit::Store::InMemory.new

    assert_equal "null", render("{{getvar::missing}}", variables: store)
    assert_equal "null", render("{{getglobalvar::missing}}", variables: store)

    # Upstream quirk: setdefaultvar checks `if(!getChatVar(name))`, but getChatVar
    # returns the string "null" for missing variables (truthy in JS). Therefore
    # missing variables do NOT get defaulted by this macro.
    assert_equal "null", render("{{setdefaultvar::x::999}}{{getvar::x}}", variables: store, run_var: true)

    # Upstream: addvar uses Number(getChatVar(name)). Number("null") => NaN.
    assert_equal "NaN", render("{{addvar::y::2}}{{getvar::y}}", variables: store, run_var: true)
  end

  def test_call_stack_limit
    input = "{{#func loop}}{{call::loop}}{{/}}{{call::loop}}"
    assert_equal "ERROR: Call stack limit reached", render(input)
  end

  def test_file_and_comment_display_mode
    encoded = Base64.strict_encode64("hello")

    assert_equal "hello", render("{{file::name.txt::#{encoded}}}")
    assert_equal "<br><div class=\"risu-file\">name.txt</div><br>", render("{{file::name.txt::#{encoded}}}", displaying: true)

    assert_equal "", render("{{comment::hi}}")
    assert_equal "<div class=\"risu-comment\">hi</div>", render("{{comment::hi}}", displaying: true)
  end

  def test_bkspc_and_erase
    assert_equal "hello user", render("hello world {{bkspc}} user")
    assert_equal "Hello world. done", render("Hello world. Next {{erase}} done")
    assert_equal "end", render("No punctuation {{erase}}end")
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

  def test_aggregate_unicode_and_crypto_macros
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (min/max/sum/average/fixnum/unicode/hex/xor/crypt)

    assert_equal "2", render("{{min::5::2::8}}")
    assert_equal "0", render("{{min::a::5}}")
    assert_equal "2", render("{{min::[\"5\",\"2\",\"8\"]}}")
    assert_equal "Infinity", render("{{min}}")

    assert_equal "8", render("{{max::5::2::8}}")
    assert_equal "5", render("{{max::a::5}}")
    assert_equal "-Infinity", render("{{max}}")

    assert_equal "6", render("{{sum::1::2::3}}")
    assert_equal "2", render("{{sum::a::2}}")
    assert_equal "0", render("{{sum}}")

    assert_equal "4", render("{{average::2::4::6}}")
    assert_equal "NaN", render("{{average}}")

    assert_equal "3.14", render("{{fixnum::3.14159::2}}")
    assert_equal "3", render("{{fixnum::3.1}}")
    assert_equal "NaN", render("{{fixnum::abc::2}}")

    assert_equal "65", render("{{unicodeencode::A}}")
    assert_equal "NaN", render("{{unicodeencode::A::1}}")
    assert_equal "A", render("{{unicodedecode::65}}")
    assert_equal "A", render("{{u::41}}")
    assert_equal "A", render("{{ue::41}}")

    assert_equal "255", render("{{fromhex::FF}}")
    assert_equal "NaN", render("{{fromhex::ZZ}}")
    assert_equal "ff", render("{{tohex::255}}")
    assert_equal "3", render("{{tohex::3.14}}")

    expected_xor = Base64.strict_encode64("hello".bytes.map { |b| b ^ 0xFF }.pack("C*"))
    assert_equal expected_xor, render("{{xor::hello}}")
    assert_equal "hello", render("{{xordecrypt::#{expected_xor}}}")
    assert_equal "hello", render("{{xordecrypt::{{xor::hello}}}}")

    assert_equal "bcd", render("{{crypt::abc::1}}")
    assert_equal "abc", render("{{crypt::bcd::-1}}")
  end

  def test_misc_macros
    assert_equal "7", render("{{calc::1 + 2 * 3}}")

    assert_equal "xy", render("x{{hidden_key::dragon}}y")
    assert_equal "eulav_emos::esrever", render("{{reverse::some_value}}")

    assert_equal "xy", render("x{{comment::hi}}y")

    assert_equal "$$E=mc^2$$", render("{{tex::E=mc^2}}")
    assert_equal "$$E=mc^2$$", render("{{latex::E=mc^2}}")

    assert_equal "<ruby>KANJI<rp> (</rp><rt>kana</rt><rp>) </rp></ruby>", render("{{ruby::KANJI::kana}}")

    assert_equal "<pre><code>puts &quot;hi&quot;</code></pre>", render("{{codeblock::puts \"hi\"}}")
    assert_equal "<pre-hljs-placeholder lang=\"ruby\">puts &quot;hi&quot;</pre-hljs-placeholder>", render("{{codeblock::ruby::puts \"hi\"}}")
  end

  def test_history_macros
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (trigger_id/previous*chat/lastmessage/firstmsgindex/blank)

    char = TavernKit::Character.create(name: "Seraphina", first_mes: "HELLO", alternate_greetings: ["ALT0", "ALT1"])

    history = [
      { role: "user", content: "u0" },
      { role: "assistant", content: "a0" },
      { role: "user", content: "u1" },
    ]

    assert_equal "u1", render("{{lastmessage}}", character: char, history: history)
    assert_equal "2", render("{{lastmessageid}}", character: char, history: history)

    assert_equal "a0", render("{{previouscharchat}}", character: char, history: history, chat_index: -1, greeting_index: -1)
    assert_equal "", render("{{previoususerchat}}", character: char, history: history, chat_index: -1, greeting_index: -1)

    assert_equal "u0", render("{{previoususerchat}}", character: char, history: history, chat_index: 2, greeting_index: -1)
    assert_equal "a0", render("{{previouscharchat}}", character: char, history: history, chat_index: 2, greeting_index: -1)

    assert_equal "HELLO", render("{{previoususerchat}}", character: char, history: [{ role: "assistant", content: "a0" }], chat_index: 1, greeting_index: -1)
    assert_equal "ALT1", render("{{previouscharchat}}", character: char, history: [], chat_index: -1, greeting_index: 1)

    assert_equal "-1", render("{{firstmsgindex}}", greeting_index: -1)
    assert_equal "2", render("{{firstmessageindex}}", greeting_index: 2)

    assert_equal "xy", render("x{{blank}}y")
    assert_equal "xy", render("x{{none}}y")

    assert_equal "abc", render("{{trigger_id}}", metadata: { "triggerid" => "abc" })
    assert_equal "null", render("{{triggerid}}", metadata: {})
  end

  def test_app_state_macros_are_metadata_backed
    user = TavernKit::User.new(name: "Alice", persona: "")

    assert_equal "SYS=Alice", render("{{mainprompt}}", user: user, metadata: { "mainprompt" => "SYS={{user}}" })
    assert_equal "SYS=Alice", render("{{systemprompt}}", user: user, metadata: { "systemprompt" => "SYS={{user}}" })

    assert_equal "JB", render("{{jb}}", metadata: { "jb" => "JB" })
    assert_equal "JB", render("{{jailbreak}}", metadata: { "jailbreak" => "JB" })

    assert_equal "NOTE", render("{{globalnote}}", metadata: { "globalnote" => "NOTE" })
    assert_equal "NOTE", render("{{systemnote}}", metadata: { "systemnote" => "NOTE" })
    assert_equal "NOTE", render("{{ujb}}", metadata: { "ujb" => "NOTE" })

    assert_equal "1", render("{{jbtoggled}}", metadata: { "jbtoggled" => true })
    assert_equal "0", render("{{jbtoggled}}", metadata: { "jbtoggled" => false })
    assert_equal "0", render("{{jbtoggled}}", metadata: {})

    assert_equal "8192", render("{{maxcontext}}", metadata: { "maxcontext" => 8192 })

    assert_equal "1", render("{{moduleenabled::core}}", modules: ["core"])
    assert_equal "0", render("{{moduleenabled::core}}", modules: [])
  end

  def test_date_and_time_macros_with_custom_format
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (date/time)
    # resources/Risuai/src/ts/parser.svelte.ts (dateTimeFormat token replacement)

    old_tz = ENV["TZ"]
    ENV["TZ"] = "UTC"

    ts_ms = 1_640_995_200_000 # 2022-01-01 00:00:00 UTC

    assert_equal "2022-01-01", render("{{date::YYYY-MM-DD::#{ts_ms}}}")
    assert_equal "2022-01-01", render("{{datetimeformat::YYYY-MM-DD::#{ts_ms}}}")
    assert_equal "Jan January", render("{{date::MMM MMMM::#{ts_ms}}}")
    assert_equal "1", render("{{date::DDDD::#{ts_ms}}}") # day-of-year

    assert_equal "00:00:00", render("{{time::HH:mm:ss::#{ts_ms}}}")
    assert_equal "12", render("{{time::hh::#{ts_ms}}}") # 12-hour clock at midnight
    assert_equal "AM", render("{{time::A::#{ts_ms}}}")
  ensure
    ENV["TZ"] = old_tz
  end

  def test_logic_and_comparison_macros
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (equal/notequal/greater/less/greaterequal/lessequal/and/or/not/all/any)

    assert_equal "1", render("{{equal::a::a}}")
    assert_equal "0", render("{{equal::a::b}}")
    assert_equal "1", render("{{notequal::a::b}}")
    assert_equal "1", render("{{not_equal::a::b}}")

    assert_equal "1", render("{{greater::2::1}}")
    assert_equal "0", render("{{greater::1::2}}")
    assert_equal "0", render("{{greater::a::1}}") # NaN > 1 => false

    assert_equal "1", render("{{less::1::2}}")
    assert_equal "0", render("{{less::2::1}}")

    assert_equal "1", render("{{greaterequal::2::2}}")
    assert_equal "1", render("{{greater_equal::2::2}}")
    assert_equal "1", render("{{lessequal::2::2}}")
    assert_equal "1", render("{{less_equal::2::2}}")

    assert_equal "1", render("{{and::1::1}}")
    assert_equal "0", render("{{and::1::0}}")
    assert_equal "1", render("{{or::0::1}}")
    assert_equal "0", render("{{or::0::0}}")
    assert_equal "0", render("{{not::1}}")
    assert_equal "1", render("{{not::0}}")
    assert_equal "1", render("{{not::true}}") # only "1" is treated as true

    assert_equal "1", render("{{all::1::1::1}}")
    assert_equal "0", render("{{all::1::0::1}}")
    assert_equal "1", render("{{all::[\"1\",\"1\"]}}")

    assert_equal "1", render("{{any::0::1::0}}")
    assert_equal "0", render("{{any::0::0}}")
    assert_equal "1", render("{{any::[\"0\",\"1\"]}}")
  end

  def test_array_and_dict_macros
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (dictelement/objectassert/element/arrayshift/arraypop/arraypush/arraysplice/arrayassert/makearray/makedict/range/filter)

    assert_equal "John", render("{{dictelement::{\"name\":\"John\"}::name}}")
    assert_equal "John", render("{{objectelement::{\"name\":\"John\"}::name}}")

    assert_equal "{\"a\":1,\"b\":\"2\"}", render("{{objectassert::{\"a\":1}::b::2}}")
    assert_equal "{\"a\":1,\"b\":\"2\"}", render("{{object_assert::{\"a\":1}::b::2}}")

    nested = ::JSON.generate({ "user" => ::JSON.generate({ "name" => "John" }) })
    assert_equal "John", render("{{element::#{nested}::user::name}}")
    assert_equal "null", render("{{element::{\"n\":0}::n}}") # JS falsy quirk

    assert_equal "[\"b\",\"c\"]", render("{{arrayshift::[\"a\",\"b\",\"c\"]}}")
    assert_equal "[\"a\",\"b\"]", render("{{arraypop::[\"a\",\"b\",\"c\"]}}")
    assert_equal "[\"a\",\"b\",\"c\"]", render("{{arraypush::[\"a\",\"b\"]::c}}")
    assert_equal "[\"a\",\"x\",\"c\"]", render("{{arraysplice::[\"a\",\"b\",\"c\"]::1::1::x}}")
    assert_equal "[\"a\",null,null,null,null,\"b\"]", render("{{arrayassert::[\"a\"]::5::b}}")

    assert_equal "[\"a\",\"b\",\"c\"]", render("{{makearray::a::b::c}}")
    assert_equal "[\"a\",\"b\",\"c\"]", render("{{array::a::b::c}}")
    assert_equal "[\"a\",\"b\",\"c\"]", render("{{a::a::b::c}}")

    assert_equal "{\"name\":\"John\",\"age\":\"25\"}", render("{{makedict::name=John::age=25}}")
    assert_equal "{\"name\":\"John\",\"age\":\"25\"}", render("{{dict::name=John::age=25}}")

    assert_equal "[\"0\",\"1\",\"2\",\"3\",\"4\"]", render("{{range::[5]}}")
    assert_equal "[\"2\",\"4\",\"6\"]", render("{{range::[2,8,2]}}")

    assert_equal "[\"a\",\"\"]", render("{{filter::[\"a\",\"\",\"a\"]::unique}}")
    assert_equal "[\"a\",\"a\"]", render("{{filter::[\"a\",\"\",\"a\"]::nonempty}}")
    assert_equal "[\"a\"]", render("{{filter::[\"a\",\"\",\"a\"]::all}}")
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

  def test_metadata_macros_are_app_injected
    # Upstream reference:
    # resources/Risuai/src/ts/cbs.ts (metadata/iserror)

    assert_equal "gpt-4o", render("{{metadata::modelName}}", metadata: { "modelname" => "gpt-4o" })
    assert_equal "1", render("{{metadata::mobile}}", metadata: { "mobile" => true })
    assert_equal "0", render("{{metadata::node}}", metadata: { "node" => false })
    assert_equal "{\"a\":1}", render("{{metadata::obj}}", metadata: { "obj" => { a: 1 } })

    err = render("{{metadata::unknown_key}}", metadata: {})
    assert_match(/\AError:/, err)
    assert_equal "1", render("{{iserror::#{err}}}")
    assert_equal "0", render("{{iserror::ok}}")
  end
end
