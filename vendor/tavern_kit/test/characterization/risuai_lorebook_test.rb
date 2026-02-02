# frozen_string_literal: true

require "test_helper"

class RisuaiLorebookTest < Minitest::Test
  # Upstream references:
  # - resources/Risuai/src/ts/lorebook/*.ts @ b8076cae
  # - docs/compatibility/risuai-deltas.md (tracked deltas)

  def test_full_word_matching
    lore = {
      key: "dragon",
      secondkey: "",
      selective: false,
      alwaysActive: false,
      insertorder: 100,
      content: "L-DRAGON",
    }
    messages = ["The red dragon sleeps"]

    result = TavernKit::RisuAI::Lorebook.match(
      messages,
      [lore],
      full_word_matching: true,
      scan_depth: 5,
      recursive_scanning: false
    )

    assert_equal ["L-DRAGON"], result.prompts
  end

  def test_selective_requires_secondkey
    lore = {
      key: "dragon",
      secondkey: "cave",
      selective: true,
      alwaysActive: false,
      insertorder: 100,
      content: "L-SELECTIVE",
    }
    messages = ["A dragon appears."]

    result = TavernKit::RisuAI::Lorebook.match(
      messages,
      [lore],
      scan_depth: 5
    )

    assert_equal [], result.prompts
  end

  def test_regex_matching
    lore = {
      key: "/drag(on|oon)/i",
      secondkey: "",
      selective: false,
      useRegex: true,
      alwaysActive: false,
      insertorder: 100,
      content: "L-REGEX",
    }
    messages = ["A DRAGOON appears."]

    result = TavernKit::RisuAI::Lorebook.match(
      messages,
      [lore],
      scan_depth: 5
    )

    assert_equal ["L-REGEX"], result.prompts
  end

  def test_decorators_depth_and_injection
    lores = [
      {
        key: "dragon",
        content: "@@depth 1\nL-DEPTH",
        insertorder: 100,
        alwaysActive: false,
        selective: false,
      },
      {
        key: "dragon",
        content: "@@inject_at L-DEPTH\nL-INJECT",
        insertorder: 90,
        alwaysActive: false,
        selective: false,
      },
    ]
    messages = ["dragon"]

    result = TavernKit::RisuAI::Lorebook.match(messages, lores, scan_depth: 5)

    assert_includes result.prompts, "L-DEPTH"
    assert_includes result.prompts, "L-INJECT"
  end
end
