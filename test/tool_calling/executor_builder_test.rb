# frozen_string_literal: true

require_relative "test_helper"

require "fileutils"
require "tmpdir"

class ToolCallingExecutorBuilderTest < Minitest::Test
  ToolDefinition = TavernKit::VibeTavern::ToolsBuilder::Definition

  class DefaultExecutor
    def call(name:, args:, tool_call_id: nil)
      {
        ok: true,
        tool_name: name,
        data: { routed: "default", args: args, tool_call_id: tool_call_id },
        warnings: [],
        errors: [],
      }
    end
  end

  class McpClient
    def call_tool(name:, arguments:)
      {
        "content" => [{ "type" => "text", "text" => "echo: #{arguments.fetch("text", "")}" }],
        "structuredContent" => { "tool" => name, "arguments" => arguments },
        "isError" => false,
      }
    end
  end

  def build_runner_config(context)
    TavernKit::VibeTavern::RunnerConfig.build(
      provider: "openrouter",
      model: "test-model",
      context: context,
    )
  end

  def test_returns_nil_when_tool_use_mode_disabled
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(name: "state_get", description: "Read state", parameters: { type: "object", properties: {} }),
        ],
      )

    runner_config =
      build_runner_config(
        tool_calling: { tool_use_mode: :disabled },
      )

    surface = TavernKit::VibeTavern::ToolsBuilder.build(runner_config: runner_config, base_catalog: base)

    executor =
      TavernKit::VibeTavern::ToolCalling::ExecutorBuilder.build(
        runner_config: runner_config,
        registry: surface,
        default_executor: DefaultExecutor.new,
      )

    assert_nil executor
  end

  def test_requires_default_executor_for_non_prefixed_tools
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(name: "state_get", description: "Read state", parameters: { type: "object", properties: {} }),
        ],
      )

    runner_config =
      build_runner_config(
        tool_calling: { tool_use_mode: :relaxed },
      )

    surface = TavernKit::VibeTavern::ToolsBuilder.build(runner_config: runner_config, base_catalog: base)

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::ToolCalling::ExecutorBuilder.build(
        runner_config: runner_config,
        registry: surface,
      )
    end
  end

  def test_reserved_skills_prefix_requires_skills_enabled
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(name: "skills_list", description: "Reserved", parameters: { type: "object", properties: {} }),
        ],
      )

    runner_config =
      build_runner_config(
        skills: { enabled: false },
        tool_calling: { tool_use_mode: :relaxed },
      )

    surface = TavernKit::VibeTavern::ToolsBuilder.build(runner_config: runner_config, base_catalog: base)

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::ToolCalling::ExecutorBuilder.build(
        runner_config: runner_config,
        registry: surface,
      )
    end
  end

  def test_builds_skills_executor_when_skills_tools_visible
    Dir.mktmpdir do |dir|
      skills_root = File.join(dir, "skills_root")
      skill_dir = File.join(skills_root, "foo")
      FileUtils.mkdir_p(skill_dir)
      File.write(
        File.join(skill_dir, "SKILL.md"),
        <<~MD,
          ---
          name: foo
          description: Foo skill
          ---
          # Foo
        MD
      )

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)

      runner_config =
        build_runner_config(
          skills: { enabled: true, store: store, include_location: false },
          tool_calling: { tool_use_mode: :relaxed },
        )

      surface =
        TavernKit::VibeTavern::ToolsBuilder.build(
          runner_config: runner_config,
          base_catalog: TavernKit::VibeTavern::Tools::Custom::Catalog.new,
        )

      executor =
        TavernKit::VibeTavern::ToolCalling::ExecutorBuilder.build(
          runner_config: runner_config,
          registry: surface,
        )

      assert_kind_of TavernKit::VibeTavern::ToolCalling::ExecutorRouter, executor

      result = executor.call(name: "skills_list", args: {})
      assert_equal true, result.fetch(:ok)
      skills = result.fetch(:data).fetch(:skills)
      assert_equal ["foo"], skills.map { |s| s.fetch(:name) }
    end
  end

  def test_requires_mcp_snapshot_for_mcp_tools
    runner_config =
      build_runner_config(
        tool_calling: { tool_use_mode: :relaxed },
      )

    mcp_defs =
      [
        ToolDefinition.new(
          name: "mcp_fake__echo",
          description: "Echo (MCP)",
          parameters: { type: "object", properties: {} },
        ),
      ]

    surface =
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: TavernKit::VibeTavern::Tools::Custom::Catalog.new,
        mcp_definitions: mcp_defs,
      )

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::ToolCalling::ExecutorBuilder.build(
        runner_config: runner_config,
        registry: surface,
      )
    end
  end

  def test_builds_mcp_executor_when_mcp_tools_visible
    runner_config =
      build_runner_config(
        tool_calling: { tool_use_mode: :relaxed },
      )

    mcp_defs =
      [
        ToolDefinition.new(
          name: "mcp_fake__echo",
          description: "Echo (MCP)",
          parameters: { type: "object", properties: {} },
        ),
      ]

    snapshot =
      TavernKit::VibeTavern::Tools::MCP::Snapshot.new(
        definitions: [],
        mapping: { "mcp_fake__echo" => { server_id: "fake", remote_tool_name: "echo" } },
        clients: { "fake" => McpClient.new },
      )

    surface =
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: TavernKit::VibeTavern::Tools::Custom::Catalog.new,
        mcp_definitions: mcp_defs,
      )

    executor =
      TavernKit::VibeTavern::ToolCalling::ExecutorBuilder.build(
        runner_config: runner_config,
        registry: surface,
        mcp_snapshot: snapshot,
      )

    assert_kind_of TavernKit::VibeTavern::ToolCalling::ExecutorRouter, executor

    result = executor.call(name: "mcp_fake__echo", args: { "text" => "hello" })
    assert_equal true, result.fetch(:ok)
    assert_includes result.dig(:data, :text), "echo: hello"
    assert_equal "fake", result.dig(:data, :mcp, :server_id)
    assert_equal "echo", result.dig(:data, :mcp, :remote_tool_name)
  end

  def test_allow_deny_filtering_can_hide_reserved_tools
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(name: "skills_list", description: "Reserved", parameters: { type: "object", properties: {} }),
          ToolDefinition.new(name: "state_get", description: "State", parameters: { type: "object", properties: {} }),
        ],
      )

    runner_config =
      build_runner_config(
        tool_calling: { tool_use_mode: :relaxed, tool_denylist: ["skills_list"] },
      )

    surface = TavernKit::VibeTavern::ToolsBuilder.build(runner_config: runner_config, base_catalog: base)

    executor =
      TavernKit::VibeTavern::ToolCalling::ExecutorBuilder.build(
        runner_config: runner_config,
        registry: surface,
        default_executor: DefaultExecutor.new,
      )

    assert_kind_of TavernKit::VibeTavern::ToolCalling::ExecutorRouter, executor

    result = executor.call(name: "state_get", args: {})
    assert_equal true, result.fetch(:ok)
    assert_equal "default", result.fetch(:data).fetch(:routed)
  end
end
