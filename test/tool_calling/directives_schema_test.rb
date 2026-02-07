# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/directives/schema"

class DirectivesSchemaTest < Minitest::Test
  def test_schema_hash_omits_type_enum_when_types_not_provided
    schema = TavernKit::VibeTavern::Directives::Schema.schema_hash
    type_prop = schema.dig(:properties, :directives, :items, :properties, :type)

    assert_equal "string", type_prop.fetch(:type)
    refute type_prop.key?(:enum)
  end

  def test_schema_hash_includes_type_enum_when_types_are_provided
    schema = TavernKit::VibeTavern::Directives::Schema.schema_hash(types: %w[ui.toast ui.show_form])
    type_prop = schema.dig(:properties, :directives, :items, :properties, :type)

    assert_equal %w[ui.toast ui.show_form], type_prop.fetch(:enum)
  end
end
