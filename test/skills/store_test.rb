# frozen_string_literal: true

require_relative "test_helper"

class SkillsStoreTest < Minitest::Test
  def test_store_contract_methods_raise_not_implemented
    store = TavernKit::VibeTavern::Tools::Skills::Store.new

    assert_raises(NotImplementedError) { store.list_skills }
    assert_raises(NotImplementedError) { store.load_skill(name: "x") }
    assert_raises(NotImplementedError) { store.read_skill_file(name: "x", rel_path: "references/x.md", max_bytes: 1) }
  end
end
