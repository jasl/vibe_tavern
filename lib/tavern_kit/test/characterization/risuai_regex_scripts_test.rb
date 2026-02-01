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
end
