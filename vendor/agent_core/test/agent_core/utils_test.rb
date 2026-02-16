# frozen_string_literal: true

require "test_helper"

class AgentCore::UtilsTest < Minitest::Test
  def test_symbolize_keys_nil
    assert_equal({}, AgentCore::Utils.symbolize_keys(nil))
  end

  def test_symbolize_keys_string_key
    assert_equal({ model: "m" }, AgentCore::Utils.symbolize_keys({ "model" => "m" }))
  end

  def test_symbolize_keys_symbol_wins_over_string
    input = { model: "a", "model" => "b" }
    assert_equal({ model: "a" }, AgentCore::Utils.symbolize_keys(input))
  end

  def test_deep_symbolize_keys
    input = {
      "a" => 1,
      "b" => [{ "c" => 2 }],
      d: { "e" => 3 },
    }

    assert_equal(
      { a: 1, b: [{ c: 2 }], d: { e: 3 } },
      AgentCore::Utils.deep_symbolize_keys(input),
    )
  end

  def test_normalize_mcp_tool_definition
    raw = { "name" => "read_file", "description" => "Read a file", "inputSchema" => { "type" => "object" } }
    normalized = AgentCore::Utils.normalize_mcp_tool_definition(raw)

    assert_equal "read_file", normalized[:name]
    assert_equal "Read a file", normalized[:description]
    assert_equal({ "type" => "object" }, normalized[:input_schema])
  end

  def test_normalize_mcp_tool_definition_nil_when_name_blank
    assert_nil AgentCore::Utils.normalize_mcp_tool_definition({ "name" => "  " })
  end

  def test_normalize_mcp_tool_call_result_maps_is_error
    raw = { "content" => [{ "type" => "text", "text" => "oops" }], "isError" => true }
    normalized = AgentCore::Utils.normalize_mcp_tool_call_result(raw)

    assert_equal [{ type: :text, text: "oops" }], normalized[:content]
    assert_equal true, normalized[:error]
    assert_equal({}, normalized[:metadata])
  end

  def test_normalize_mcp_tool_call_result_falls_back_to_text
    normalized = AgentCore::Utils.normalize_mcp_tool_call_result("not a hash")
    assert_equal [{ type: :text, text: "not a hash" }], normalized[:content]
    assert_equal false, normalized[:error]
    assert_equal({}, normalized[:metadata])
  end

  def test_normalize_mcp_tool_call_result_preserves_structured_content
    raw = { "content" => [{ "type" => "text", "text" => "ok" }], "structuredContent" => { "answer" => 42 } }
    normalized = AgentCore::Utils.normalize_mcp_tool_call_result(raw)

    assert_equal({ structured_content: { "answer" => 42 } }, normalized[:metadata])
  end

  def test_normalize_mcp_tool_call_result_normalizes_image_blocks
    raw = {
      "content" => [
        {
          "type" => "image",
          "data" => "QUJD",
          "mime_type" => "image/png",
        },
      ],
    }
    normalized = AgentCore::Utils.normalize_mcp_tool_call_result(raw)

    assert_equal(
      [{ type: :image, source_type: :base64, data: "QUJD", media_type: "image/png" }],
      normalized[:content],
    )
  end

  def test_parse_tool_arguments_blank
    args, err = AgentCore::Utils.parse_tool_arguments("   ")
    assert_equal({}, args)
    assert_nil err
  end

  def test_parse_tool_arguments_json_string
    args, err = AgentCore::Utils.parse_tool_arguments("{\"a\":1}")
    assert_equal({ "a" => 1 }, args)
    assert_nil err
  end

  def test_parse_tool_arguments_fenced_json_string
    args, err = AgentCore::Utils.parse_tool_arguments("```json\n{\"a\":1}\n```")
    assert_equal({ "a" => 1 }, args)
    assert_nil err
  end

  def test_parse_tool_arguments_double_encoded_json_string
    raw = "\"{\\\"a\\\":1}\""
    args, err = AgentCore::Utils.parse_tool_arguments(raw)
    assert_equal({ "a" => 1 }, args)
    assert_nil err
  end

  def test_parse_tool_arguments_hash
    args, err = AgentCore::Utils.parse_tool_arguments({ "a" => 1, "b" => { "c" => 2 } })
    assert_equal({ "a" => 1, "b" => { "c" => 2 } }, args)
    assert_nil err
  end

  def test_parse_tool_arguments_array_is_invalid
    args, err = AgentCore::Utils.parse_tool_arguments([1, 2, 3])
    assert_equal({}, args)
    assert_equal :invalid_json, err
  end

  def test_parse_tool_arguments_too_large
    long_value = "x" * 10
    args, err = AgentCore::Utils.parse_tool_arguments("{\"a\":\"#{long_value}\"}", max_bytes: 5)
    assert_equal({}, args)
    assert_equal :too_large, err
  end

  def test_normalize_tool_call_id_ensures_unique_and_fills_blank
    used = {}
    id1 = AgentCore::Utils.normalize_tool_call_id("", used: used, fallback: "tc_1")
    id2 = AgentCore::Utils.normalize_tool_call_id("tc_1", used: used, fallback: "tc_2")
    id3 = AgentCore::Utils.normalize_tool_call_id("tc_1", used: used, fallback: "tc_3")

    assert_equal "tc_1", id1
    assert_equal "tc_1__2", id2
    assert_equal "tc_1__3", id3
  end

  def test_normalize_json_schema_omits_empty_required_arrays
    schema = {
      "type" => "object",
      "properties" => { "a" => { "type" => "string", "required" => [] } },
      "required" => [],
    }

    normalized = AgentCore::Utils.normalize_json_schema(schema)

    refute normalized.key?("required")
    refute normalized.dig("properties", "a").key?("required")
  end

  def test_truncate_utf8_bytes_handles_invalid_utf8
    invalid = "\xC3".dup.force_encoding(Encoding::UTF_8)
    out = AgentCore::Utils.truncate_utf8_bytes(invalid, max_bytes: 1)

    assert out.valid_encoding?
    assert out.bytesize <= 1
  end
end
