# frozen_string_literal: true

require_relative "test_helper"

require "easy_talk"

require_relative "../../lib/tavern_kit/vibe_tavern/json_schema"
require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/tool_registry"

class JsonSchemaTest < Minitest::Test
  class ExampleSchema
    include EasyTalk::Schema

    define_schema do
      description "Example schema"
      property :a, String, optional: true
    end
  end

  class ExampleModel
    include EasyTalk::Model

    define_schema do
      property :name, String, min_length: 1
    end
  end

  def test_coerce_returns_hash_for_hash
    h = { type: "object", properties: {} }
    assert_equal h, TavernKit::VibeTavern::JsonSchema.coerce(h)
  end

  def test_coerce_supports_objects_with_json_schema
    schema = TavernKit::VibeTavern::JsonSchema.coerce(ExampleSchema)
    assert_equal "object", schema.fetch("type")
    refute schema.key?("required")
  end

  def test_coerce_supports_objects_with_to_json_schema
    meta = ExampleModel.new(name: "ok").to_json_schema
    assert meta.is_a?(Hash)

    schema = TavernKit::VibeTavern::JsonSchema.coerce(ExampleModel.new(name: "ok"))
    assert_equal meta.fetch(:schema), schema
  end

  def test_coerce_raises_for_unknown_provider
    err = assert_raises(ArgumentError) { TavernKit::VibeTavern::JsonSchema.coerce("nope") }
    assert_match(/Unsupported schema provider/, err.message)
  end

  def test_tool_definition_accepts_easy_talk_schema_provider
    tool =
      TavernKit::VibeTavern::ToolCalling::ToolDefinition.new(
        name: "example",
        description: "Example",
        parameters: ExampleSchema,
      )

    openai_tool = tool.to_openai_tool
    params = openai_tool.dig(:function, :parameters)
    assert_equal ExampleSchema.json_schema, params
    refute params.key?("required")
  end
end
