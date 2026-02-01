# frozen_string_literal: true

require "test_helper"

class RisuaiTriggersTest < Minitest::Test
  def pending!(reason)
    skip("Pending RisuAI parity: #{reason}")
  end

  def test_condition_var_true
    trigger = {
      type: "output",
      conditions: [{ type: "var", var: "flag", value: "", operator: "true" }],
      effect: [{ type: "setvar", var: "hit", value: "yes", operator: "=" }],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { scriptstate: { "$flag" => "1" }, message: [] }
    )

    assert_equal "yes", result.chat[:scriptstate]["$hit"]
  end

  def test_systemprompt_appends_to_additional_sys_prompt
    trigger = {
      type: "output",
      effect: [{ type: "systemprompt", location: "start", value: "SYS" }],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { message: [] }
    )

    assert_equal "SYS\n\n", result.chat[:additional_sys_prompt][:start]
  end

  def test_impersonate_appends_to_chat_message
    trigger = {
      type: "output",
      effect: [{ type: "impersonate", role: "user", value: "Hello" }],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { message: [] }
    )

    assert_equal [{ role: "user", data: "Hello" }], result.chat[:message]
  end

  def test_extract_regex_sets_var_only_with_low_level_access
    trigger = {
      type: "output",
      lowLevelAccess: true,
      effect: [{
        type: "extractRegex",
        value: "abc123",
        regex: "(\\d+)",
        flags: "",
        result: "$1",
        inputVar: "num",
      }],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { scriptstate: {}, message: [] }
    )
    assert_equal "123", result.chat[:scriptstate]["$num"]

    trigger2 = trigger.merge(lowLevelAccess: false)
    result2 = TavernKit::RisuAI::Triggers.run(
      trigger2,
      chat: { scriptstate: {}, message: [] }
    )
    assert_nil result2.chat[:scriptstate]["$num"]
  end

  def test_cutchat_slices_message_list
    trigger = {
      type: "output",
      effect: [{ type: "cutchat", start: "1", end: "3" }],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: {
        message: [
          { role: "user", data: "m0" },
          { role: "user", data: "m1" },
          { role: "user", data: "m2" },
          { role: "user", data: "m3" },
        ],
      }
    )

    assert_equal ["m1", "m2"], result.chat[:message].map { |m| m[:data] }
  end

  def test_modifychat_updates_message_at_index
    trigger = {
      type: "output",
      effect: [{ type: "modifychat", index: "1", value: "X" }],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: {
        message: [
          { role: "user", data: "m0" },
          { role: "user", data: "m1" },
        ],
      }
    )

    assert_equal "X", result.chat[:message][1][:data]
  end

  def test_run_all_supports_runtrigger_by_comment_with_recursion_limit
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (runtrigger recursionCount < 10)

    triggers = [
      {
        type: "output",
        comment: "A",
        conditions: [],
        effect: [{ type: "runtrigger", value: "B" }],
      },
      {
        type: "manual",
        comment: "B",
        conditions: [],
        effect: [{ type: "setvar", operator: "=", var: "hit", value: "yes" }],
      },
    ]

    result = TavernKit::RisuAI::Triggers.run_all(
      triggers,
      chat: { scriptstate: {}, message: [] }
    )

    assert_equal "yes", result.chat[:scriptstate]["$hit"]

    # Recursion is blocked at 10 for non-lowLevelAccess triggers.
    triggers2 = [
      {
        type: "output",
        comment: "A",
        conditions: [],
        effect: [{ type: "runtrigger", value: "A" }],
      },
    ]

    result2 = TavernKit::RisuAI::Triggers.run_all(
      triggers2,
      chat: { scriptstate: {}, message: [] }
    )

    # It should return without infinite recursion and without setting anything.
    assert_equal({}, result2.chat[:scriptstate])
  end

  def test_condition_exists_modes
    trigger = {
      type: "output",
      conditions: [{ type: "exists", value: "Dragon", type2: "loose", depth: 2 }],
      effect: [{ type: "setvar", var: "hit", value: "yes", operator: "=" }],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { message: [{ data: "a dragon" }, { data: "sleeps" }] }
    )

    assert_equal "yes", result.chat[:scriptstate]["$hit"]
  end

  def test_v2_if_membership
    trigger = {
      type: "output",
      effect: [
        { type: "v2IfAdvanced", condition: "∈", sourceType: "value", source: "a", targetType: "value", target: "[\"a\",\"b\"]", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "yes", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { scriptstate: {}, message: [] }
    )

    assert_equal "yes", result.chat[:scriptstate]["$hit"]
  end

  def test_v2_effects_do_not_disable_v1_effects
    trigger = {
      type: "output",
      effect: [
        { type: "v2IfAdvanced", condition: "∈", sourceType: "value", source: "a", targetType: "value", target: "[\"a\"]", indent: 0 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
        { type: "setvar", var: "hit", value: "yes", operator: "=" },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { scriptstate: {}, message: [] }
    )

    assert_equal "yes", result.chat[:scriptstate]["$hit"]
  end

  def test_v2_if_else
    trigger = {
      type: "output",
      effect: [
        { type: "v2IfAdvanced", condition: "=", sourceType: "value", source: "0", targetType: "value", target: "1", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "IF", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
        { type: "v2Else", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "ELSE", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "ELSE", result.chat[:scriptstate]["$hit"]

    trigger2 = trigger.dup
    trigger2[:effect] = trigger[:effect].dup
    trigger2[:effect][0] = trigger2[:effect][0].merge(source: "1", target: "1")
    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "IF", result2.chat[:scriptstate]["$hit"]
  end

  def test_v2_if_approx_and_equivalent
    trigger = {
      type: "output",
      effect: [
        { type: "v2IfAdvanced", condition: "≒", sourceType: "value", source: "1", targetType: "value", target: "1.00005", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "YES", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "YES", result.chat[:scriptstate]["$hit"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2IfAdvanced", condition: "≡", sourceType: "value", source: "1", targetType: "value", target: "true", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "YES", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "YES", result2.chat[:scriptstate]["$hit"]
  end
end
