# frozen_string_literal: true

require_relative "test_helper"

require "fileutils"
require "tmpdir"

require_relative "../../lib/tavern_kit/vibe_tavern/tools_builder"

class ToolsBuilderTest < Minitest::Test
  ToolDefinition = TavernKit::VibeTavern::ToolsBuilder::Definition

  def test_builds_snapshot_catalog
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(
            name: "state_get",
            description: "Read state",
            parameters: { type: "object", properties: {} },
          ),
        ],
      )

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: { tool_calling: { tool_use_mode: :relaxed } },
      )

    surface =
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: base,
      )

    assert_kind_of TavernKit::VibeTavern::ToolsBuilder::CatalogSnapshot, surface

    names = surface.openai_tools(expose: :model).map { |t| t.dig(:function, :name) }.compact
    assert_includes names, "state_get"
  end

  def test_includes_skills_tools
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
        TavernKit::VibeTavern::RunnerConfig.build(
          provider: "openrouter",
          model: "test-model",
          context: {
            skills: { enabled: true, store: store, include_location: false },
            tool_calling: { tool_use_mode: :relaxed },
          },
        )

      surface =
        TavernKit::VibeTavern::ToolsBuilder.build(
          runner_config: runner_config,
          base_catalog: TavernKit::VibeTavern::Tools::Custom::Catalog.new,
        )

      names = surface.openai_tools(expose: :model).map { |t| t.dig(:function, :name) }.compact
      assert_includes names, "skills_list"
      assert_includes names, "skills_load"
      assert_includes names, "skills_read_file"
    end
  end

  def test_includes_mcp_tools
    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: { tool_calling: { tool_use_mode: :relaxed } },
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

    names = surface.openai_tools(expose: :model).map { |t| t.dig(:function, :name) }.compact
    assert_includes names, "mcp_fake__echo"
  end

  def test_raises_on_duplicate_tool_names_across_sources
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(
            name: "skills_list",
            description: "Conflicts with built-in",
            parameters: { type: "object", properties: {} },
          ),
        ],
      )

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
        TavernKit::VibeTavern::RunnerConfig.build(
          provider: "openrouter",
          model: "test-model",
          context: {
            skills: { enabled: true, store: store, include_location: false },
            tool_calling: { tool_use_mode: :relaxed },
          },
        )

      assert_raises(ArgumentError) do
        TavernKit::VibeTavern::ToolsBuilder.build(runner_config: runner_config, base_catalog: base)
      end
    end
  end

  def test_surface_limits_raise_from_tools_builder
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(name: "tool_0", description: "x", parameters: { type: "object", properties: {} }),
          ToolDefinition.new(name: "tool_1", description: "x", parameters: { type: "object", properties: {} }),
          ToolDefinition.new(name: "tool_2", description: "x", parameters: { type: "object", properties: {} }),
        ],
      )

    runner_config =
      TavernKit::VibeTavern::RunnerConfig.build(
        provider: "openrouter",
        model: "test-model",
        context: {
          tool_calling: { tool_use_mode: :relaxed, max_tool_definitions_count: 1 },
        },
      )

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: base,
      )
    end
  end

  def test_allow_deny_is_applied_before_snapshot_limits
    base =
      TavernKit::VibeTavern::Tools::Custom::Catalog.new(
        definitions: [
          ToolDefinition.new(name: "tool_0", description: "x", parameters: { type: "object", properties: {} }),
          ToolDefinition.new(name: "tool_1", description: "x", parameters: { type: "object", properties: {} }),
          ToolDefinition.new(name: "tool_2", description: "x", parameters: { type: "object", properties: {} }),
        ],
      )

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

    surface =
      TavernKit::VibeTavern::ToolsBuilder.build(
        runner_config: runner_config,
        base_catalog: base,
      )

    names = surface.openai_tools(expose: :model).map { |t| t.dig(:function, :name) }.compact
    assert_equal ["tool_0"], names
  end
end
