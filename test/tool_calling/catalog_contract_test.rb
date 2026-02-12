# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/tools_builder/catalog"

class ToolCallingCatalogContractTest < Minitest::Test
  def test_catalog_contract_methods_raise_not_implemented
    catalog = TavernKit::VibeTavern::ToolsBuilder::Catalog.new

    assert_raises(NotImplementedError) { catalog.definitions }
    assert_raises(NotImplementedError) { catalog.openai_tools }
    assert_raises(NotImplementedError) { catalog.include?("state_get") }
  end
end
