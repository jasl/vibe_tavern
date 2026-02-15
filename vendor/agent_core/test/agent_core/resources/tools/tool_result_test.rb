# frozen_string_literal: true

require "test_helper"
require "json"

class AgentCore::Resources::Tools::ToolResultTest < Minitest::Test
  ToolResult = AgentCore::Resources::Tools::ToolResult

  def test_success_factory
    result = ToolResult.success(text: "file contents")
    refute result.error?
    assert_equal "file contents", result.text
  end

  def test_error_factory
    result = ToolResult.error(text: "not found")
    assert result.error?
    assert_equal "not found", result.text
  end

  def test_with_content_factory
    blocks = [{ type: :text, text: "a" }, { type: :image, source_type: :base64, data: "x", media_type: "image/png" }]
    result = ToolResult.with_content(blocks)

    refute result.error?
    assert_equal 2, result.content.size
  end

  def test_text_concatenation
    result = ToolResult.new(
      content: [
        { type: :text, text: "line 1" },
        { type: :image, data: "x" },
        { type: :text, text: "line 2" },
      ],
    )

    assert_equal "line 1\nline 2", result.text
  end

  def test_has_non_text_content
    result = ToolResult.new(
      content: [
        { type: :text, text: "a" },
        { type: :image, data: "x" },
      ],
    )

    assert result.has_non_text_content?
  end

  def test_has_non_text_content_false
    result = ToolResult.success(text: "only text")
    refute result.has_non_text_content?
  end

  def test_normalize_string_block
    result = ToolResult.new(content: ["plain string"])
    assert_equal :text, result.content.first[:type]
    assert_equal "plain string", result.content.first[:text]
  end

  def test_normalize_string_type_to_symbol
    result = ToolResult.new(content: [{ "type" => "text", "text" => "hello" }])
    assert_equal :text, result.content.first[:type]
    assert_equal "hello", result.content.first[:text]
  end

  def test_normalize_missing_type_with_text_key
    result = ToolResult.new(content: [{ text: "auto-typed" }])
    assert_equal :text, result.content.first[:type]
  end

  def test_content_frozen
    result = ToolResult.success(text: "ok")
    assert result.content.frozen?
  end

  def test_metadata
    result = ToolResult.success(text: "ok", metadata: { elapsed_ms: 42 })
    assert_equal({ elapsed_ms: 42 }, result.metadata)
    assert result.metadata.frozen?
  end

  def test_metadata_defaults_to_empty
    result = ToolResult.success(text: "ok")
    assert_equal({}, result.metadata)
  end

  def test_to_h
    result = ToolResult.success(text: "ok")
    h = result.to_h

    assert_equal false, h[:error]
    assert_instance_of Array, h[:content]
    assert_instance_of Hash, h[:metadata]
  end

  def test_error_coercion
    result = ToolResult.new(content: [{ type: :text, text: "x" }], error: nil)
    assert_equal false, result.error?

    result = ToolResult.new(content: [{ type: :text, text: "x" }], error: "truthy")
    assert result.error?
  end

  def test_normalize_source_type_string_to_symbol
    result = ToolResult.new(
      content: [{ type: :image, source_type: "base64", data: "x", media_type: "image/png" }],
    )
    assert_equal :base64, result.content.first[:source_type]
  end

  def test_from_h_symbolizes_metadata_keys
    input = {
      "content" => [{ "type" => "text", "text" => "ok" }],
      "error" => false,
      "metadata" => { "duration_ms" => 1.5 },
    }

    result = ToolResult.from_h(input)

    refute result.error?
    assert_equal "ok", result.text
    assert_equal 1.5, result.metadata.fetch(:duration_ms)
  end

  def test_from_h_accepts_json_string
    json = JSON.generate({ content: [{ type: "text", text: "oops" }], error: true, metadata: {} })
    result = ToolResult.from_h(json)

    assert result.error?
    assert_equal "oops", result.text
  end

  def test_from_h_raises_on_non_array_content
    assert_raises(ArgumentError) do
      ToolResult.from_h({ content: "nope", error: false, metadata: {} })
    end
  end

  def test_from_h_raises_on_non_hash_metadata
    assert_raises(ArgumentError) do
      ToolResult.from_h({ content: [], error: false, metadata: "nope" })
    end
  end
end
