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

    assert_equal [{ "type" => "text", "text" => "oops" }], normalized[:content]
    assert_equal true, normalized[:error]
  end

  def test_normalize_mcp_tool_call_result_falls_back_to_text
    normalized = AgentCore::Utils.normalize_mcp_tool_call_result("not a hash")
    assert_equal [{ type: :text, text: "not a hash" }], normalized[:content]
    assert_equal false, normalized[:error]
  end
end
