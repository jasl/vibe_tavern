# frozen_string_literal: true

require "test_helper"

class InjectionRegistryContractTest < Minitest::Test
  # Contract reference:
  # - lib/tavern_kit/docs/contracts/prompt-orchestration.md (strict/tolerant error policy and injection registry behavior)
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/injects", __dir__)

  def test_each_yields_entry_objects_in_lexicographic_id_order
    fixture = JSON.parse(File.read(File.join(FIXTURES_DIR, "basic.json")))

    registry = TavernKit::SillyTavern::InjectionRegistry.from_st_json(fixture)
    entries = registry.each.to_a

    assert entries.all? { |e| e.is_a?(TavernKit::InjectionRegistry::Entry) }
    assert_equal entries.map(&:id).sort, entries.map(&:id)
  end

  def test_filter_is_treated_as_external_input_and_is_tolerant
    fixture = JSON.parse(File.read(File.join(FIXTURES_DIR, "basic.json")))

    registry = TavernKit::SillyTavern::InjectionRegistry.from_st_json(fixture)
    delta = registry.each.find { |e| e.id == "delta" }

    ctx = TavernKit::Prompt::Context.new
    ctx.warning_handler = nil

    assert delta.active_for?(ctx)
    assert_includes ctx.warnings.first, "Unsupported ST filter closure ignored"

    strict_ctx = TavernKit::Prompt::Context.new
    strict_ctx.warning_handler = nil
    strict_ctx.strict = true

    assert_raises(TavernKit::StrictModeError) do
      delta.active_for?(strict_ctx)
    end
  end
end
