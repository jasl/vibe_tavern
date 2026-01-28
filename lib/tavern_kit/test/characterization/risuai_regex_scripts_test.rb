# frozen_string_literal: true

require "test_helper"

class RisuaiRegexScriptsTest < Minitest::Test
  def pending!(reason)
    skip("Pending RisuAI parity: #{reason}")
  end

  def test_ordering_and_flags
    pending!("Regex scripts ordered by <order N> and sanitized flags")

    scripts = [
      { in: "a", out: "A", type: "editinput", flag: "<order 10>", ableFlag: true },
      { in: "a", out: "B", type: "editinput", flag: "", ableFlag: true },
    ]

    result = TavernKit::Risuai::RegexScripts.apply(
      "a",
      scripts,
      mode: "editinput"
    )

    assert_equal "A", result
  end

  def test_move_top_and_move_bottom
    pending!("@@move_top / @@move_bottom directives")

    scripts = [
      { in: "dragon", out: "@@move_top DRAGON", type: "editoutput" },
      { in: "knight", out: "@@move_bottom KNIGHT", type: "editoutput" },
    ]

    result = TavernKit::Risuai::RegexScripts.apply(
      "dragon meets knight",
      scripts,
      mode: "editoutput"
    )

    assert_equal "DRAGON\ndragon meets knight\nKNIGHT", result
  end

  def test_repeat_back
    pending!("@@repeat_back behavior using previous same-role message")

    scripts = [
      { in: "flag:(\\w+)", out: "@@repeat_back end", type: "editoutput" },
    ]

    history = [
      { role: "user", data: "flag:alpha" },
      { role: "char", data: "flag:beta" },
    ]

    result = TavernKit::Risuai::RegexScripts.apply(
      "current flag:gamma",
      scripts,
      mode: "editoutput",
      chat_id: 2,
      history: history,
      role: "char"
    )

    assert_equal "current flag:gamma flag:beta", result
  end
end
