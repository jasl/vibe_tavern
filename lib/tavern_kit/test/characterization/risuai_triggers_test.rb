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

  def test_setvar_arithmetic_uses_js_number_semantics
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (setvar)

    trigger = {
      type: "output",
      conditions: [],
      effect: [
        { type: "setvar", operator: "=", var: "x", value: "10" },
        { type: "setvar", operator: "+=", var: "x", value: "2" },
        { type: "setvar", operator: "-=", var: "x", value: "1" },
        { type: "setvar", operator: "*=", var: "x", value: "2" },
        { type: "setvar", operator: "/=", var: "x", value: "2" },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "11", result.chat[:scriptstate]["$x"]

    nan_trigger = {
      type: "output",
      effect: [
        { type: "setvar", operator: "=", var: "x", value: "10" },
        { type: "setvar", operator: "+=", var: "x", value: "abc" },
      ],
    }
    result2 = TavernKit::RisuAI::Triggers.run(nan_trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "NaN", result2.chat[:scriptstate]["$x"]

    inf_trigger = {
      type: "output",
      effect: [
        { type: "setvar", operator: "=", var: "x", value: "10" },
        { type: "setvar", operator: "/=", var: "x", value: "0" },
      ],
    }
    result3 = TavernKit::RisuAI::Triggers.run(inf_trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "Infinity", result3.chat[:scriptstate]["$x"]
  end

  def test_triggers_can_use_core_chat_variables_store_as_scriptstate
    store = TavernKit::ChatVariables::InMemory.new
    store.set("flag", "1", scope: :local)

    trigger = {
      type: "output",
      conditions: [{ type: "var", var: "flag", value: "", operator: "true" }],
      effect: [{ type: "setvar", var: "hit", value: "yes", operator: "=" }],
    }

    _result = TavernKit::RisuAI::Triggers.run(trigger, chat: { message: [], variables: store })

    assert_equal "yes", store.get("hit", scope: :local)
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

  def test_v2_local_vars_declare_clear_and_cross_trigger_visibility
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2DeclareLocalVar + clearLocalVarsAtIndent + getVar)

    trigger = {
      type: "output",
      effect: [
        { type: "v2DeclareLocalVar", var: "x", valueType: "value", value: "1", indent: 0 },
        { type: "v2IfAdvanced", condition: "=", sourceType: "var", source: "x", targetType: "value", target: "1", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "YES", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "YES", result.chat[:scriptstate]["$hit"]
    assert_nil result.chat[:scriptstate]["$x"] # locals do not persist to scriptstate

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2IfAdvanced", condition: "=", sourceType: "value", source: "1", targetType: "value", target: "1", indent: 0 },
        { type: "v2DeclareLocalVar", var: "x", valueType: "value", value: "A", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
        # x should have been cleared; this if body must not run.
        { type: "v2IfAdvanced", condition: "=", sourceType: "var", source: "x", targetType: "value", target: "A", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "BAD", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "OK", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "OK", result2.chat[:scriptstate]["$hit"]

    triggers = [
      { type: "output", comment: "A", conditions: [], effect: [{ type: "v2DeclareLocalVar", var: "x", valueType: "value", value: "1", indent: 0 }] },
      { type: "output", comment: "B", conditions: [{ type: "var", var: "x", value: "1", operator: "=" }], effect: [{ type: "setvar", operator: "=", var: "hit", value: "yes" }] },
    ]

    result3 = TavernKit::RisuAI::Triggers.run_all(triggers, chat: { scriptstate: {}, message: [] })
    assert_equal "yes", result3.chat[:scriptstate]["$hit"]
  end

  def test_v2_setvar_supports_arithmetic_operators
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2SetVar)

    trigger = {
      type: "output",
      effect: [
        { type: "v2SetVar", operator: "=", var: "x", valueType: "value", value: "10", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "y", valueType: "value", value: "2", indent: 0 },
        { type: "v2SetVar", operator: "+=", var: "x", valueType: "var", value: "y", indent: 0 },
        { type: "v2SetVar", operator: "%=", var: "x", valueType: "value", value: "3", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "0", result.chat[:scriptstate]["$x"]
  end

  def test_v2_loop_and_loop_n_times
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2Loop/v2LoopNTimes/v2EndIndent endOfLoop)

    trigger = {
      type: "output",
      effect: [
        { type: "v2LoopNTimes", valueType: "value", value: "3", indent: 0 },
        { type: "v2SetVar", operator: "+=", var: "x", valueType: "value", value: "1", indent: 1 },
        { type: "v2EndIndent", endOfLoop: true, indent: 1 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "3", result.chat[:scriptstate]["$x"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2Loop", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "1", indent: 1 },
        { type: "v2BreakLoop", indent: 1 },
        { type: "v2EndIndent", endOfLoop: true, indent: 1 },
        { type: "v2SetVar", operator: "=", var: "after", valueType: "value", value: "OK", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "1", result2.chat[:scriptstate]["$hit"]
    assert_equal "OK", result2.chat[:scriptstate]["$after"]
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

  def test_display_and_request_modes_apply_effect_allowlists
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (displayAllowList/requestAllowList)

    trigger = {
      type: "display",
      conditions: [],
      effect: [
        # v1 effects are skipped in display mode
        { type: "setvar", operator: "=", var: "hit", value: "V1" },
        # v2 safeSubset effects are allowed
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "V2", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "V2", result.chat[:scriptstate]["$hit"]

    trigger2 = trigger.merge(type: "request")
    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "V2", result2.chat[:scriptstate]["$hit"]

    assert TavernKit::RisuAI::Triggers.effect_allowed?("v2Random", mode: "display")
    assert TavernKit::RisuAI::Triggers.effect_allowed?("v2RegexTest", mode: "request")
    refute TavernKit::RisuAI::Triggers.effect_allowed?("v2Loop", mode: "display")
    refute TavernKit::RisuAI::Triggers.effect_allowed?("v2RunTrigger", mode: "request")
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

  def test_v2_random_sets_number_in_range
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2Random)

    trigger = {
      type: "output",
      effect: [
        { type: "v2Random", minType: "value", min: "1", maxType: "value", max: "3", outputVar: "x", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    x = Integer(result.chat[:scriptstate]["$x"], exception: false)
    refute_nil x
    assert_includes 1..3, x
  end

  def test_v2_regex_test_sets_one_or_zero
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2RegexTest)

    trigger = {
      type: "output",
      effect: [
        { type: "v2RegexTest", valueType: "value", value: "cat", regexType: "value", regex: "a", flagsType: "value", flags: "", outputVar: "hit", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "1", result.chat[:scriptstate]["$hit"]

    trigger2 = trigger.dup
    trigger2[:effect] = [
      { type: "v2RegexTest", valueType: "value", value: "cat", regexType: "value", regex: "(", flagsType: "value", flags: "", outputVar: "hit", indent: 0 },
    ]

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "0", result2.chat[:scriptstate]["$hit"]
  end

  def test_v2_extract_regex_formats_placeholders
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2ExtractRegex)

    trigger = {
      type: "output",
      effect: [{
        type: "v2ExtractRegex",
        valueType: "value",
        value: "abc123",
        regexType: "value",
        regex: "(\\d+)",
        flagsType: "value",
        flags: "",
        resultType: "value",
        result: "$1 $$ $&",
        outputVar: "out",
        indent: 0,
      }],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "123 $ 123", result.chat[:scriptstate]["$out"]

    trigger2 = trigger.dup
    trigger2[:effect] = trigger[:effect].dup
    trigger2[:effect][0] = trigger2[:effect][0].merge(value: "no match")
    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal " $ ", result2.chat[:scriptstate]["$out"]
  end

  def test_v2_stop_trigger_halts_processing
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2StopTrigger)

    trigger = {
      type: "output",
      effect: [
        { type: "v2StopTrigger", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "BAD", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_nil result.chat[:scriptstate]["$hit"]
  end

  def test_v2_console_log_appends_to_chat_state
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2ConsoleLog)

    trigger = {
      type: "output",
      effect: [
        { type: "v2ConsoleLog", sourceType: "value", source: "hello", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal ["hello"], result.chat[:console_log]
  end

  def test_v2_if_works_like_v2_if_advanced_with_source_var
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2If)

    trigger = {
      type: "output",
      effect: [
        { type: "v2SetVar", operator: "=", var: "x", valueType: "value", value: "1", indent: 0 },
        { type: "v2If", condition: "=", source: "x", targetType: "value", target: "1", indent: 0 },
        { type: "v2SetVar", operator: "=", var: "hit", valueType: "value", value: "yes", indent: 1 },
        { type: "v2EndIndent", endOfLoop: false, indent: 1 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "yes", result.chat[:scriptstate]["$hit"]
  end

  def test_v2_string_primitives
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2GetCharAt/v2GetCharCount/v2ToLowerCase/v2ToUpperCase/v2SetCharAt/v2ConcatString)

    trigger = {
      type: "output",
      effect: [
        { type: "v2GetCharAt", sourceType: "value", source: "abc", indexType: "value", index: "1", outputVar: "ch", indent: 0 },
        { type: "v2GetCharAt", sourceType: "value", source: "abc", indexType: "value", index: "-1", outputVar: "ch2", indent: 0 },
        { type: "v2GetCharCount", sourceType: "value", source: "abc", outputVar: "len", indent: 0 },
        { type: "v2ToLowerCase", sourceType: "value", source: "AbC", outputVar: "lower", indent: 0 },
        { type: "v2ToUpperCase", sourceType: "value", source: "AbC", outputVar: "upper", indent: 0 },
        { type: "v2SetCharAt", sourceType: "value", source: "abc", indexType: "value", index: "1", valueType: "value", value: "Z", outputVar: "set", indent: 0 },
        { type: "v2ConcatString", source1Type: "value", source1: "a", source2Type: "value", source2: "b", outputVar: "cat", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "b", result.chat[:scriptstate]["$ch"]
    assert_equal "null", result.chat[:scriptstate]["$ch2"]
    assert_equal "3", result.chat[:scriptstate]["$len"]
    assert_equal "abc", result.chat[:scriptstate]["$lower"]
    assert_equal "ABC", result.chat[:scriptstate]["$upper"]
    assert_equal "aZc", result.chat[:scriptstate]["$set"]
    assert_equal "ab", result.chat[:scriptstate]["$cat"]
  end
end
