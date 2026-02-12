# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/tools_builder/catalog_snapshot"

class ToolCallingCatalogSnapshotLimitsTest < Minitest::Test
  def build_tool(name, description: "x", exposed_to_model: true)
    TavernKit::VibeTavern::ToolsBuilder::Definition.new(
      name: name,
      description: description,
      exposed_to_model: exposed_to_model,
      parameters: { type: "object", properties: {} },
    )
  end

  def test_build_from_raises_when_count_limit_exceeded
    defs = 129.times.map { |i| build_tool("tool_#{i}") }
    registry = TavernKit::VibeTavern::Tools::Custom::Catalog.new(definitions: defs)

    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::ToolsBuilder::CatalogSnapshot.build_from(
          base_catalog: registry,
          max_count: 128,
          max_bytes: 1_000_000,
        )
      end

    assert_includes error.message, "max_tool_definitions_count"
  end

  def test_build_from_raises_when_bytes_limit_exceeded
    defs = [build_tool("big", description: "a" * 10_000)]
    registry = TavernKit::VibeTavern::Tools::Custom::Catalog.new(definitions: defs)

    error =
      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::ToolsBuilder::CatalogSnapshot.build_from(
          base_catalog: registry,
          max_count: 128,
          max_bytes: 200,
        )
      end

    assert_includes error.message, "max_tool_definitions_bytes"
  end

  def test_hidden_tools_do_not_count_toward_limits
    defs = []

    190.times do |i|
      defs << build_tool("hidden_#{i}", exposed_to_model: false)
    end

    10.times do |i|
      defs << build_tool("tool_#{i}")
    end

    registry = TavernKit::VibeTavern::Tools::Custom::Catalog.new(definitions: defs)

    snapshot =
      TavernKit::VibeTavern::ToolsBuilder::CatalogSnapshot.build_from(
        base_catalog: registry,
        max_count: 128,
        max_bytes: 1_000_000,
      )

    assert_equal 10, snapshot.openai_tools(expose: :model).size
    assert_equal true, snapshot.include?("tool_0", expose: :model)
    assert_equal false, snapshot.include?("hidden_0", expose: :model)
  end
end
