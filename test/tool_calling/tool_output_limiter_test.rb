# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/tool_output_limiter"

class ToolOutputLimiterTest < Minitest::Test
  def test_check_rejects_large_string
    big = "x" * 1000
    result =
      TavernKit::VibeTavern::ToolCalling::ToolOutputLimiter.check(
        { "data" => big },
        max_bytes: 100,
      )

    assert_equal false, result.fetch(:ok)
    assert_includes result.fetch(:reason), "TOO_LARGE"
  end

  def test_check_rejects_excessive_depth
    nested = { "a" => { "b" => { "c" => { "d" => { "e" => "ok" } } } } }
    result =
      TavernKit::VibeTavern::ToolCalling::ToolOutputLimiter.check(
        nested,
        max_bytes: 10_000,
        max_depth: 2,
      )

    assert_equal false, result.fetch(:ok)
    assert_equal "MAX_DEPTH", result.fetch(:reason)
  end

  def test_check_rejects_excessive_nodes
    value = Array.new(100) { |i| { "n" => i } }
    result =
      TavernKit::VibeTavern::ToolCalling::ToolOutputLimiter.check(
        value,
        max_bytes: 10_000,
        max_nodes: 10,
      )

    assert_equal false, result.fetch(:ok)
    assert_equal "MAX_NODES", result.fetch(:reason)
  end

  def test_check_accepts_small_value
    result =
      TavernKit::VibeTavern::ToolCalling::ToolOutputLimiter.check(
        { ok: true, data: { value: "hi" } },
        max_bytes: 100,
      )

    assert_equal true, result.fetch(:ok)
    assert result.fetch(:estimated_bytes).is_a?(Integer)
  end
end
