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

  def test_v2_split_string_and_join_array_var
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2SplitString/v2JoinArrayVar)

    trigger = {
      type: "output",
      effect: [
        { type: "v2SplitString", sourceType: "value", source: "a,b", delimiterType: "value", delimiter: ",", outputVar: "arr", indent: 0 },
        { type: "v2JoinArrayVar", varType: "var", var: "arr", delimiterType: "value", delimiter: "-", outputVar: "joined", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "[\"a\",\"b\"]", result.chat[:scriptstate]["$arr"]
    assert_equal "a-b", result.chat[:scriptstate]["$joined"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2SplitString", sourceType: "value", source: "a  b", delimiterType: "regex", delimiter: "/\\s+/", outputVar: "arr", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "[\"a\",\"b\"]", result2.chat[:scriptstate]["$arr"]

    trigger3 = {
      type: "output",
      effect: [
        { type: "v2SplitString", sourceType: "value", source: "x", delimiterType: "regex", delimiter: "(", outputVar: "arr", indent: 0 },
        { type: "v2JoinArrayVar", varType: "value", var: "invalid json", delimiterType: "value", delimiter: ",", outputVar: "joined", indent: 0 },
      ],
    }

    result3 = TavernKit::RisuAI::Triggers.run(trigger3, chat: { scriptstate: {}, message: [] })
    assert_equal "[\"x\"]", result3.chat[:scriptstate]["$arr"]
    assert_equal "", result3.chat[:scriptstate]["$joined"]
  end

  def test_v2_array_var_operations
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2MakeArrayVar + array CRUD effects)

    trigger = {
      type: "output",
      effect: [
        { type: "v2MakeArrayVar", var: "arr", indent: 0 },
        { type: "v2PushArrayVar", var: "arr", valueType: "value", value: "a", indent: 0 },
        { type: "v2PushArrayVar", var: "arr", valueType: "value", value: "b", indent: 0 },
        { type: "v2GetArrayVarLength", var: "arr", outputVar: "len", indent: 0 },
        { type: "v2GetArrayVar", var: "arr", indexType: "value", index: "1", outputVar: "second", indent: 0 },
        { type: "v2PopArrayVar", var: "arr", outputVar: "popped", indent: 0 },
        { type: "v2ShiftArrayVar", var: "arr", outputVar: "shifted", indent: 0 },
        { type: "v2GetArrayVarLength", var: "arr", outputVar: "len2", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "[]", result.chat[:scriptstate]["$arr"]
    assert_equal "2", result.chat[:scriptstate]["$len"]
    assert_equal "b", result.chat[:scriptstate]["$second"]
    assert_equal "b", result.chat[:scriptstate]["$popped"]
    assert_equal "a", result.chat[:scriptstate]["$shifted"]
    assert_equal "0", result.chat[:scriptstate]["$len2"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2SetVar", operator: "=", var: "arr", valueType: "value", value: "[\"a\",\"c\"]", indent: 0 },
        { type: "v2SpliceArrayVar", var: "arr", startType: "value", start: "1", itemType: "value", item: "b", indent: 0 },
        { type: "v2SliceArrayVar", var: "arr", startType: "value", start: "1", endType: "value", end: "3", outputVar: "slice", indent: 0 },
        { type: "v2GetIndexOfValueInArrayVar", var: "arr", valueType: "value", value: "b", outputVar: "idx", indent: 0 },
        { type: "v2RemoveIndexFromArrayVar", var: "arr", indexType: "value", index: "1", indent: 0 },
        { type: "v2SetArrayVar", var: "arr", indexType: "value", index: "1", valueType: "value", value: "Z", indent: 0 },
        { type: "v2GetArrayVar", var: "arr", indexType: "value", index: "1", outputVar: "val", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "[\"b\",\"c\"]", result2.chat[:scriptstate]["$slice"]
    assert_equal "1", result2.chat[:scriptstate]["$idx"]
    assert_equal "Z", result2.chat[:scriptstate]["$val"]

    trigger3 = {
      type: "output",
      effect: [
        { type: "v2SetVar", operator: "=", var: "bad", valueType: "value", value: "invalid json", indent: 0 },
        { type: "v2PushArrayVar", var: "bad", valueType: "value", value: "x", indent: 0 },
      ],
    }

    result3 = TavernKit::RisuAI::Triggers.run(trigger3, chat: { scriptstate: {}, message: [] })
    assert_equal "[]", result3.chat[:scriptstate]["$bad"]
  end

  def test_v2_calculate_substitutes_vars_and_evaluates_expression
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2Calculate + $var parseFloat substitution)

    trigger = {
      type: "output",
      effect: [
        { type: "v2SetVar", operator: "=", var: "x", valueType: "value", value: "2", indent: 0 },
        { type: "v2Calculate", expressionType: "value", expression: "$x+3*2", outputVar: "out", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "8", result.chat[:scriptstate]["$out"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2SetVar", operator: "=", var: "x", valueType: "value", value: "10abc", indent: 0 },
        { type: "v2Calculate", expressionType: "value", expression: "$x+1", outputVar: "out", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "11", result2.chat[:scriptstate]["$out"]

    trigger3 = {
      type: "output",
      effect: [
        { type: "v2Calculate", expressionType: "value", expression: "(", outputVar: "out", indent: 0 },
      ],
    }

    result3 = TavernKit::RisuAI::Triggers.run(trigger3, chat: { scriptstate: {}, message: [] })
    assert_equal "0", result3.chat[:scriptstate]["$out"]
  end

  def test_v2_display_and_request_state_effects_use_chat_display_data
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2GetDisplayState/v2SetDisplayState + requestAllowList effects)

    display_trigger = {
      type: "display",
      effect: [
        { type: "v2SetDisplayState", valueType: "value", value: "X", indent: 0 },
        { type: "v2GetDisplayState", outputVar: "out", indent: 0 },
      ],
    }

    display_result = TavernKit::RisuAI::Triggers.run(display_trigger, chat: { scriptstate: {}, message: [], display_data: "null" })
    assert_equal "X", display_result.chat[:display_data]
    assert_equal "X", display_result.chat[:scriptstate]["$out"]

    request_state = [
      { "role" => "user", "content" => "hi" },
      { "role" => "assistant", "content" => "ok" },
    ]

    request_trigger = {
      type: "request",
      effect: [
        { type: "v2GetRequestStateLength", outputVar: "len", indent: 0 },
        { type: "v2GetRequestState", indexType: "value", index: "0", outputVar: "m0", indent: 0 },
        { type: "v2GetRequestStateRole", indexType: "value", index: "0", outputVar: "r0", indent: 0 },
        { type: "v2SetRequestState", indexType: "value", index: "1", valueType: "value", value: "OK2", indent: 0 },
        { type: "v2SetRequestStateRole", indexType: "value", index: "0", valueType: "value", value: "system", indent: 0 },
        { type: "v2GetRequestState", indexType: "value", index: "1", outputVar: "m1", indent: 0 },
        { type: "v2GetRequestStateRole", indexType: "value", index: "0", outputVar: "r0b", indent: 0 },
      ],
    }

    request_result = TavernKit::RisuAI::Triggers.run(
      request_trigger,
      chat: { scriptstate: {}, message: [], display_data: JSON.generate(request_state) }
    )

    assert_equal "2", request_result.chat[:scriptstate]["$len"]
    assert_equal "hi", request_result.chat[:scriptstate]["$m0"]
    assert_equal "user", request_result.chat[:scriptstate]["$r0"]
    assert_equal "OK2", request_result.chat[:scriptstate]["$m1"]
    assert_equal "system", request_result.chat[:scriptstate]["$r0b"]

    json = JSON.parse(request_result.chat[:display_data])
    assert_equal "OK2", json[1]["content"]
    assert_equal "system", json[0]["role"]
  end

  def test_v2_dict_var_operations
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2MakeDictVar + dict CRUD effects)

    trigger = {
      type: "output",
      effect: [
        { type: "v2MakeDictVar", var: "d", indent: 0 },
        { type: "v2SetDictVar", varType: "var", var: "d", keyType: "value", key: "k", valueType: "value", value: "v", indent: 0 },
        { type: "v2GetDictVar", varType: "var", var: "d", keyType: "value", key: "k", outputVar: "out", indent: 0 },
        { type: "v2HasDictKey", varType: "var", var: "d", keyType: "value", key: "k", outputVar: "has", indent: 0 },
        { type: "v2GetDictSize", varType: "var", var: "d", outputVar: "size", indent: 0 },
        { type: "v2GetDictKeys", varType: "var", var: "d", outputVar: "keys", indent: 0 },
        { type: "v2GetDictValues", varType: "var", var: "d", outputVar: "vals", indent: 0 },
        { type: "v2DeleteDictKey", varType: "var", var: "d", keyType: "value", key: "k", indent: 0 },
        { type: "v2HasDictKey", varType: "var", var: "d", keyType: "value", key: "k", outputVar: "has2", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "v", result.chat[:scriptstate]["$out"]
    assert_equal "1", result.chat[:scriptstate]["$has"]
    assert_equal "1", result.chat[:scriptstate]["$size"]
    assert_equal "[\"k\"]", result.chat[:scriptstate]["$keys"]
    assert_equal "[\"v\"]", result.chat[:scriptstate]["$vals"]
    assert_equal "0", result.chat[:scriptstate]["$has2"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2SetVar", operator: "=", var: "d", valueType: "value", value: "invalid json", indent: 0 },
        { type: "v2SetDictVar", varType: "var", var: "d", keyType: "value", key: "k", valueType: "value", value: "v", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "{\"k\":\"v\"}", result2.chat[:scriptstate]["$d"]
  end

  def test_v2_chat_operations_and_quick_search
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2GetLastMessage/v2GetMessageAtIndex/v2GetMessageCount/v2CutChat/v2ModifyChat/v2QuickSearchChat)

    chat = {
      scriptstate: {},
      message: [
        { role: "user", data: "hello dragon" },
        { role: "char", data: "hi" },
        { role: "user", data: "bye" },
      ],
    }

    trigger = {
      type: "output",
      effect: [
        { type: "v2GetMessageCount", outputVar: "count", indent: 0 },
        { type: "v2GetLastMessage", outputVar: "last", indent: 0 },
        { type: "v2GetMessageAtIndex", indexType: "value", index: "0", outputVar: "m0", indent: 0 },
        { type: "v2QuickSearchChat", valueType: "value", value: "dragon", condition: "loose", depthType: "value", depth: "2", outputVar: "has2", indent: 0 },
        { type: "v2QuickSearchChat", valueType: "value", value: "dragon", condition: "loose", depthType: "value", depth: "3", outputVar: "has3", indent: 0 },
        { type: "v2QuickSearchChat", valueType: "value", value: "dragon", condition: "loose", depthType: "value", depth: "Infinity", outputVar: "has_inf", indent: 0 },
        { type: "v2QuickSearchChat", valueType: "value", value: "dragon", condition: "loose", depthType: "value", depth: "-Infinity", outputVar: "has_neg_inf", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: chat)
    assert_equal "3", result.chat[:scriptstate]["$count"]
    assert_equal "bye", result.chat[:scriptstate]["$last"]
    assert_equal "hello dragon", result.chat[:scriptstate]["$m0"]
    assert_equal "0", result.chat[:scriptstate]["$has2"]
    assert_equal "1", result.chat[:scriptstate]["$has3"]
    assert_equal "1", result.chat[:scriptstate]["$has_inf"]
    assert_equal "0", result.chat[:scriptstate]["$has_neg_inf"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2CutChat", startType: "value", start: "1", endType: "value", end: "3", indent: 0 },
        { type: "v2ModifyChat", indexType: "value", index: "0", valueType: "value", value: "HI", indent: 0 },
        { type: "v2Impersonate", role: "user", valueType: "value", value: "X", indent: 0 },
        { type: "v2SystemPrompt", location: "start", valueType: "value", value: "SYS", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: chat)
    assert_equal ["HI", "bye", "X"], result2.chat[:message].map { |m| m[:data] }
    assert_equal "SYS\n\n", result2.chat[:additional_sys_prompt][:start]

    trigger3 = {
      type: "output",
      effect: [
        { type: "v2CutChat", startType: "value", start: "Infinity", endType: "value", end: "3", indent: 0 },
        { type: "v2GetMessageCount", outputVar: "count", indent: 0 },
      ],
    }

    result3 = TavernKit::RisuAI::Triggers.run(trigger3, chat: chat)
    assert_equal "0", result3.chat[:scriptstate]["$count"]
  end

  def test_v2_get_last_user_and_char_message
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2GetLastUserMessage/v2GetLastCharMessage)

    chat = {
      scriptstate: {},
      message: [
        { role: "user", data: "U1" },
        { role: "char", data: "C1" },
        { role: "user", data: "U2" },
      ],
    }

    trigger = {
      type: "output",
      effect: [
        { type: "v2GetLastUserMessage", outputVar: "u", indent: 0 },
        { type: "v2GetLastCharMessage", outputVar: "c", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: chat)
    assert_equal "U2", result.chat[:scriptstate]["$u"]
    assert_equal "C1", result.chat[:scriptstate]["$c"]

    trigger2 = {
      type: "output",
      effect: [
        { type: "v2GetLastCharMessage", outputVar: "c", indent: 0 },
      ],
    }

    result2 = TavernKit::RisuAI::Triggers.run(trigger2, chat: { scriptstate: {}, message: [] })
    assert_equal "null", result2.chat[:scriptstate]["$c"]
  end

  def test_v2_replace_string
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2ReplaceString)

    trigger = {
      type: "output",
      effect: [
        {
          type: "v2ReplaceString",
          sourceType: "value",
          source: "a-b-b",
          regexType: "value",
          regex: "b",
          resultType: "value",
          result: "$0",
          replacementType: "value",
          replacement: "X",
          flagsType: "value",
          flags: "",
          outputVar: "out1",
          indent: 0,
        },
        {
          type: "v2ReplaceString",
          sourceType: "value",
          source: "a-b-b",
          regexType: "value",
          regex: "b",
          resultType: "value",
          result: "$0",
          replacementType: "value",
          replacement: "X",
          flagsType: "value",
          flags: "g",
          outputVar: "out2",
          indent: 0,
        },
        {
          type: "v2ReplaceString",
          sourceType: "value",
          source: "abc",
          regexType: "value",
          regex: "a(b)c",
          resultType: "value",
          result: "$1",
          replacementType: "value",
          replacement: "X",
          flagsType: "value",
          flags: "",
          outputVar: "out3",
          indent: 0,
        },
        {
          type: "v2ReplaceString",
          sourceType: "value",
          source: "abc",
          regexType: "value",
          regex: "a(b)c",
          resultType: "value",
          result: "[$1:$0:$&:$$]",
          replacementType: "value",
          replacement: "X",
          flagsType: "value",
          flags: "",
          outputVar: "out4",
          indent: 0,
        },
        {
          type: "v2ReplaceString",
          sourceType: "value",
          source: "abc",
          regexType: "value",
          regex: "[",
          resultType: "value",
          result: "$0",
          replacementType: "value",
          replacement: "X",
          flagsType: "value",
          flags: "",
          outputVar: "out5",
          indent: 0,
        },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(trigger, chat: { scriptstate: {}, message: [] })
    assert_equal "a-X-b", result.chat[:scriptstate]["$out1"]
    assert_equal "a-X-X", result.chat[:scriptstate]["$out2"]
    assert_equal "aXc", result.chat[:scriptstate]["$out3"]
    assert_equal "[b:abc:abc:$]", result.chat[:scriptstate]["$out4"]
    assert_equal "abc", result.chat[:scriptstate]["$out5"]
  end

  def test_v2_tokenize_uses_injected_estimator
    # Upstream reference:
    # resources/Risuai/src/ts/process/triggers.ts (v2Tokenize)

    estimator_class = Class.new do
      attr_reader :seen

      def estimate(text, model_hint: nil)
        @seen = [text, model_hint]
        42
      end
    end

    estimator = estimator_class.new

    trigger = {
      type: "output",
      effect: [
        { type: "v2Tokenize", valueType: "value", value: "hello", outputVar: "t", indent: 0 },
      ],
    }

    result = TavernKit::RisuAI::Triggers.run(
      trigger,
      chat: { scriptstate: {}, message: [], token_estimator: estimator, model_hint: "gpt-4o" }
    )

    assert_equal ["hello", "gpt-4o"], estimator.seen
    assert_equal "42", result.chat[:scriptstate]["$t"]
  end
end
