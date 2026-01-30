# frozen_string_literal: true

require "test_helper"

class Wave4InjectionRegistryContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/injects", __dir__)

  def pending!(reason)
    skip("Pending Wave 4 (InjectionRegistry): #{reason}")
  end

  def test_each_yields_entry_objects_in_lexicographic_id_order
    pending!("SillyTavern::InjectionRegistry must yield InjectionRegistry::Entry objects in lexicographic id order")

    _fixture = JSON.parse(File.read(File.join(FIXTURES_DIR, "basic.json")))

    # Contract shape (pseudocode):
    # registry = TavernKit::SillyTavern::InjectionRegistry.from_st_json(_fixture)
    # entries = registry.each.to_a
    # assert entries.all? { |e| e.is_a?(TavernKit::InjectionRegistry::Entry) }
    # assert_equal entries.map(&:id).sort, entries.map(&:id)
  end

  def test_filter_is_treated_as_external_input_and_is_tolerant
    pending!("invalid filter closures should warn (strict: raise) and default to unfiltered (active), not crash generation")
  end
end
