# frozen_string_literal: true

require "test_helper"

class RisuaiRegexScriptsTest < Minitest::Test
  def pending!(reason)
    skip("Pending RisuAI parity: #{reason}")
  end

  def test_ordering_and_flags
    scripts = [
      { in: "a", out: "A", type: "editinput", flag: "<order 10>", ableFlag: true },
      { in: "a", out: "B", type: "editinput", flag: "", ableFlag: true },
    ]

    result = TavernKit::RisuAI::RegexScripts.apply(
      "a",
      scripts,
      mode: "editinput"
    )

    assert_equal "A", result
  end

  def test_move_top_and_move_bottom
    scripts = [
      { in: "dragon", out: "@@move_top DRAGON", type: "editoutput" },
      { in: "knight", out: "@@move_bottom KNIGHT", type: "editoutput" },
    ]

    result = TavernKit::RisuAI::RegexScripts.apply(
      "dragon|knight",
      scripts,
      mode: "editoutput"
    )

    assert_equal "DRAGON\n|\nKNIGHT", result
  end

  def test_repeat_back
    scripts = [
      { in: "flag:(\\w+)", out: "@@repeat_back end", type: "editoutput" },
    ]

    history = [
      { role: "user", data: "flag:alpha" },
      { role: "char", data: "flag:beta" },
    ]

    result = TavernKit::RisuAI::RegexScripts.apply(
      "current ",
      scripts,
      mode: "editoutput",
      chat_id: 1,
      history: history,
      role: "char"
    )

    assert_equal "current flag:beta", result
  end

  def test_replacement_supports_data_placeholder_and_capture_groups
    scripts = [
      { in: "(a)", out: "X{{data}}Y", type: "editoutput" },
      { in: "(b)", out: "[$1]", type: "editoutput" },
      { in: "c", out: "$$", type: "editoutput" },
    ]

    result = TavernKit::RisuAI::RegexScripts.apply(
      "abc",
      scripts,
      mode: "editoutput"
    )

    assert_equal "XaY[b]$", result
  end

  def test_replacement_output_is_reparsed_via_cbs
    scripts = [
      { in: "X", out: "{{user}}", type: "editoutput" },
    ]

    user = TavernKit::User.new(name: "Alice")
    env = TavernKit::RisuAI::CBS::Environment.build(user: user)

    result = TavernKit::RisuAI::RegexScripts.apply(
      "X",
      scripts,
      mode: "editoutput",
      environment: env,
    )

    assert_equal "Alice", result
  end

  def test_cbs_flag_parses_pattern_before_compiling_regex
    scripts = [
      { in: "{{user}}", out: "HIT", type: "editoutput", flag: "<cbs>", ableFlag: true },
    ]

    user = TavernKit::User.new(name: "Alice")
    env = TavernKit::RisuAI::CBS::Environment.build(user: user)

    assert_equal(
      "Alice",
      TavernKit::RisuAI::RegexScripts.apply(
        "Alice",
        scripts.map { |s| s.merge(flag: "", ableFlag: true) },
        mode: "editoutput",
        environment: env,
      ),
    )

    assert_equal(
      "HIT",
      TavernKit::RisuAI::RegexScripts.apply(
        "Alice",
        scripts,
        mode: "editoutput",
        environment: env,
      ),
    )
  end

  def test_emo_and_inject_directives_are_tolerant_and_do_not_pollute_output
    # Upstream reference:
    # resources/Risuai/src/ts/process/scripts.ts (@@emo / @@inject)

    scripts = [
      { in: "X", out: "@@emo smile", type: "editoutput" },
    ]
    assert_equal "aXb", TavernKit::RisuAI::RegexScripts.apply("aXb", scripts, mode: "editoutput")

    inject = [
      { in: "X", out: "@@inject", type: "editoutput" },
    ]

    # Without chat context, TavernKit treats @@inject as a no-op (tolerant).
    assert_equal "aXbX", TavernKit::RisuAI::RegexScripts.apply("aXbX", inject, mode: "editoutput")

    # With chat_id, mirror the upstream "remove match from data" behavior.
    assert_equal "ab", TavernKit::RisuAI::RegexScripts.apply("aXbX", inject, mode: "editoutput", chat_id: 0)
  end

  def test_process_script_cache_keys_include_environment_fingerprint
    cache = TavernKit::RisuAI::RegexScripts.send(:process_script_cache)
    cache.clear

    scripts = [
      { in: "X", out: "{{getvar::foo}}", type: "editoutput" },
    ]

    vars = TavernKit::ChatVariables::InMemory.new
    env = TavernKit::RisuAI::CBS::Environment.build(variables: vars)

    vars.set("foo", "Alice")
    assert_equal "Alice", TavernKit::RisuAI::RegexScripts.apply("X", scripts, mode: "editoutput", environment: env)
    assert_operator cache.size, :>, 0

    vars.set("foo", "Bob")
    assert_equal "Bob", TavernKit::RisuAI::RegexScripts.apply("X", scripts, mode: "editoutput", environment: env)
    assert_operator cache.size, :>, 1
  ensure
    cache.clear
  end
end
