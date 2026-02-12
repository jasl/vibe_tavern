# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/tool_calling/executor_router"

class ToolExecutorRouterTest < Minitest::Test
  class SkillsExecutor
    def call(name:, args:, tool_call_id: nil)
      {
        ok: true,
        tool_name: name,
        data: { routed: "skills", tool_call_id: tool_call_id, args: args },
        warnings: [],
        errors: [],
      }
    end
  end

  class McpExecutor
    def call(name:, args:)
      {
        ok: true,
        tool_name: name,
        data: { routed: "mcp", args: args },
        warnings: [],
        errors: [],
      }
    end
  end

  class DefaultExecutor
    def call(name:, args:)
      {
        ok: true,
        tool_name: name,
        data: { routed: "default", args: args },
        warnings: [],
        errors: [],
      }
    end
  end

  def test_routes_by_prefix_and_passes_tool_call_id_only_when_supported
    router =
      TavernKit::VibeTavern::ToolCalling::ExecutorRouter.new(
        skills_executor: SkillsExecutor.new,
        mcp_executor: McpExecutor.new,
        default_executor: DefaultExecutor.new,
      )

    skills = router.call(name: "skills_list", args: { "a" => 1 }, tool_call_id: "tc_1")
    assert_equal true, skills.fetch(:ok)
    assert_equal "skills", skills.fetch(:data).fetch(:routed)
    assert_equal "tc_1", skills.fetch(:data).fetch(:tool_call_id)

    mcp = router.call(name: "mcp_fake__echo", args: { "b" => 2 }, tool_call_id: "tc_2")
    assert_equal true, mcp.fetch(:ok)
    assert_equal "mcp", mcp.fetch(:data).fetch(:routed)
    refute_includes mcp.fetch(:data).keys, :tool_call_id

    default = router.call(name: "state_get", args: { "c" => 3 }, tool_call_id: "tc_3")
    assert_equal true, default.fetch(:ok)
    assert_equal "default", default.fetch(:data).fetch(:routed)
    refute_includes default.fetch(:data).keys, :tool_call_id
  end

  def test_returns_not_implemented_when_no_executor_available
    router = TavernKit::VibeTavern::ToolCalling::ExecutorRouter.new

    result = router.call(name: "skills_list", args: {})
    assert_equal false, result.fetch(:ok)
    assert_equal "TOOL_NOT_IMPLEMENTED", result.fetch(:errors).first.fetch(:code)
  end
end
