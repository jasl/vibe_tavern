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
    pending!("Trigger v2If membership operators")

    trigger = {
      type: "output",
      effect: [
        { type: "v2If", condition: "∈", sourceType: "value", source: "a", targetType: "value", target: "[\"a\",\"b\"]", indent: 0 },
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
end
