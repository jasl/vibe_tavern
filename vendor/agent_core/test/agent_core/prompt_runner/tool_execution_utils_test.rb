# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptRunner::ToolExecutionUtilsTest < Minitest::Test
  def test_summarize_tool_arguments_safe_does_not_include_values
    args = { "token" => "SECRET", "count" => 1 }

    safe = AgentCore::PromptRunner::ToolExecutionUtils.summarize_tool_arguments(args)
    refute_includes safe, "SECRET"

    debug = AgentCore::PromptRunner::ToolExecutionUtils.summarize_tool_arguments(args, mode: :debug)
    assert_includes debug, "SECRET"
  end

  def test_summarize_tool_result_safe_does_not_include_text
    result = AgentCore::Resources::Tools::ToolResult.success(text: "SECRET")

    safe = AgentCore::PromptRunner::ToolExecutionUtils.summarize_tool_result(result)
    refute_includes safe, "SECRET"

    debug = AgentCore::PromptRunner::ToolExecutionUtils.summarize_tool_result(result, mode: :debug)
    assert_includes debug, "SECRET"
  end
end
