# frozen_string_literal: true

require "test_helper"

class StMacrosTest < Minitest::Test
  # Upstream references:
  # - resources/SillyTavern/public/scripts/macros.js @ bba43f332
  # - lib/tavern_kit/docs/compatibility/sillytavern-deltas.md (tracked deltas)

  def test_legacy_marker_rewrites
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = TavernKit::SillyTavern::Macro::Environment.new(
      user_name: "Alice",
      character_name: "Nyx",
      group_name: "Alice, Nyx",
    )
    result = engine.expand("<USER> meets <BOT> in <GROUP>", environment: env)
    assert_equal "Alice meets Nyx in Alice, Nyx", result
  end

  def test_time_utc_legacy_syntax
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env =
      TavernKit::SillyTavern::Macro::Environment.new(
        clock: -> { Time.utc(2020, 1, 1, 12, 34, 0) },
      )

    result = engine.expand("{{time_UTC-10}}", environment: env)
    assert_equal "2:34 AM", result
  end

  def test_if_else_scoped_macro
    engine = TavernKit::SillyTavern::Macro::V2Engine.new

    template = "{{if .flag}}YES{{else}}NO{{/if}}"
    assert_equal "YES", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "true" }))
    assert_equal "NO", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "false" }))

    preserved = "{{#if .flag}}  YES  {{else}}  NO  {{/if}}"
    assert_equal "  YES  ", engine.expand(preserved, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "true" }))
  end

  def test_nested_macros_in_args
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    env = TavernKit::SillyTavern::Macro::Environment.new(user_name: "Bob")
    assert_equal "boB", engine.expand("{{reverse::{{user}}}}", environment: env)

    # Nested macro includes `::` in its own args; outer arg splitting must not
    # treat that as top-level separators.
    template = "{{setvar::x::Bob}}{{reverse::{{getvar::x}}}}"
    assert_equal "boB", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new)
  end

  def test_nested_macros_in_if_condition
    engine = TavernKit::SillyTavern::Macro::V2Engine.new

    template = "{{if {{getvar::flag}}}}YES{{else}}NO{{/if}}"
    assert_equal "YES", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "true" }))
    assert_equal "NO", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new(locals: { "flag" => "false" }))
  end

  def test_variable_shorthand_operators
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    text = "{{.score+=1}}{{.score}}"
    assert_equal "1", engine.expand(text, environment: TavernKit::SillyTavern::Macro::Environment.new)
  end

  def test_trim_macro_postprocessing
    engine = TavernKit::SillyTavern::Macro::V2Engine.new
    template = "A\n{{trim}}\nB"
    assert_equal "AB", engine.expand(template, environment: TavernKit::SillyTavern::Macro::Environment.new)
  end

  def test_typed_arg_validation_and_strict_mode
    registry = TavernKit::SillyTavern::Macro::Registry.new
    registry.register("num", unnamed_args: [{ name: "n", type: :integer }]) { "OK" }
    registry.register("lenient", unnamed_args: [{ name: "n", type: :integer }], strict_args: false) { "OK" }
    registry.register("block", unnamed_args: [{ name: "content", type: :integer }]) { "OK" }

    engine = TavernKit::SillyTavern::Macro::V2Engine.new(registry: registry)

    env = TavernKit::SillyTavern::Macro::Environment.new
    assert_equal "{{num}}", engine.expand("{{num}}", environment: env)
    assert_includes env.warnings.join("\n"), "expects"

    env2 = TavernKit::SillyTavern::Macro::Environment.new
    assert_equal "{{num::abc}}", engine.expand("{{num::abc}}", environment: env2)
    assert_includes env2.warnings.join("\n"), "expected type"

    env3 = TavernKit::SillyTavern::Macro::Environment.new
    assert_equal "OK", engine.expand("{{lenient::abc}}", environment: env3)
    assert_includes env3.warnings.join("\n"), "expected type"

    env4 = TavernKit::SillyTavern::Macro::Environment.new
    assert_equal "{{block}}abc{{/block}}", engine.expand("{{block}}abc{{/block}}", environment: env4)

    strict_env = TavernKit::SillyTavern::Macro::Environment.new(strict: true)
    assert_raises(TavernKit::StrictModeError) do
      engine.expand("{{lenient::abc}}", environment: strict_env)
    end
  end

  def test_registry_normalizes_metadata_keys
    registry = TavernKit::SillyTavern::Macro::Registry.new

    # Accept legacy/camelCase metadata keys, but normalize internally so the
    # macro engine only deals with snake_case symbol keys.
    registry.register(
      "num",
      unnamedArgs: [{ "name" => "n", "type" => :integer, "optional" => true }],
      list: { "min" => 1, "max" => 2 },
    ) { "OK" }

    defn = registry.get("num")

    assert_equal [{ name: "n", type: :integer, optional: true }], defn.unnamed_arg_defs
    assert_equal({ min: 1, max: 2 }, defn.list_spec)
    assert_equal 0, defn.min_args
    assert_equal 1, defn.max_args
    assert defn.arity_valid?(1)

    engine = TavernKit::SillyTavern::Macro::V2Engine.new(registry: registry)
    assert_equal "OK", engine.expand("{{num::1}}", environment: TavernKit::SillyTavern::Macro::Environment.new)
  end
end
