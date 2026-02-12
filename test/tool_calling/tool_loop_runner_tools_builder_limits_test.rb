# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/runner_config"
require_relative "../../lib/tavern_kit/vibe_tavern/prompt_runner"
require_relative "../../lib/tavern_kit/vibe_tavern/tools_builder"

class ToolLoopRunnerToolsBuilderLimitsTest < Minitest::Test
  def test_allow_deny_is_applied_before_snapshot_limits
    registry = build_registry(count: 3)

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: {
          tool_calling: {
            tool_use_mode: :relaxed,
            tool_denylist: ["tool_1", "tool_2"],
            max_tool_definitions_count: 1,
          },
        },
      )

    catalog =
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: registry,
      )

    tools = catalog.openai_tools(expose: :model)
    assert_equal 1, tools.size

    names = tools.map { |t| t.dig(:function, :name) }.compact
    assert_equal ["tool_0"], names
  end

  def build_registry(count:, description: "x")
    defs =
      count.times.map do |i|
        TavernKit::VibeTavern::ToolsBuilder::Definition.new(
          name: "tool_#{i}",
          description: description,
          parameters: { type: "object", properties: {} },
        )
      end

    TavernKit::VibeTavern::Tools::Custom::Catalog.new(definitions: defs)
  end

  def test_tool_loop_runner_raises_when_tool_count_limit_exceeded
    registry = build_registry(count: 3)

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: {
          tool_calling: {
            tool_use_mode: :relaxed,
            max_tool_definitions_count: 1,
          },
        },
      )

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: registry,
      )
    end
  end

  def test_tool_loop_runner_raises_when_tool_bytes_limit_exceeded
    registry = build_registry(count: 1, description: "a" * 10_000)

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: {
          tool_calling: {
            tool_use_mode: :relaxed,
            max_tool_definitions_bytes: 200,
          },
        },
      )

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: registry,
      )
    end
  end
end
