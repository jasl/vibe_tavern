# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class AgentCore::Resources::PromptInjections::Sources::FileSetTest < Minitest::Test
  def test_per_file_truncation_uses_head_marker_tail
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.txt"), "A" * 100)

      source =
        AgentCore::Resources::PromptInjections::Sources::FileSet.new(
          files: [{ path: "a.txt", max_bytes: 10 }],
          section_header: "Ctx",
        )

      ctx = AgentCore::ExecutionContext.from({ workspace_dir: dir })

      items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)
      assert_equal 1, items.size

      content = items.first.content
      assert_includes content, "## a.txt\nAA\n...\nAAA"
    end
  end

  def test_total_budget_truncation_uses_head_marker_tail
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.txt"), "A" * 50)
      File.write(File.join(dir, "b.txt"), "B" * 50)

      source =
        AgentCore::Resources::PromptInjections::Sources::FileSet.new(
          files: [{ path: "a.txt" }, { path: "b.txt" }],
          section_header: "Ctx",
          total_max_bytes: 60,
        )

      ctx = AgentCore::ExecutionContext.from({ workspace_dir: dir })

      items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)
      assert_equal 1, items.size

      content = items.first.content
      assert_operator content.bytesize, :<=, 60
      assert_includes content, "\n...\n"
    end
  end

  def test_missing_file_includes_marker_line
    Dir.mktmpdir do |dir|
      source =
        AgentCore::Resources::PromptInjections::Sources::FileSet.new(
          files: [{ path: "missing.txt" }],
          section_header: "Ctx",
          include_missing: true,
        )

      ctx = AgentCore::ExecutionContext.from({ workspace_dir: dir })

      items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)
      assert_equal 1, items.size

      assert_includes items.first.content, "[MISSING] missing.txt"
    end
  end

  def test_minimal_mode_filters_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "full.txt"), "FULL")
      File.write(File.join(dir, "min.txt"), "MIN")

      source =
        AgentCore::Resources::PromptInjections::Sources::FileSet.new(
          files: [
            { path: "full.txt", prompt_modes: [:full] },
            { path: "min.txt", prompt_modes: [:minimal] },
          ],
          section_header: "Ctx",
        )

      ctx = AgentCore::ExecutionContext.from({ workspace_dir: dir })

      items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :minimal)
      assert_equal 1, items.size

      content = items.first.content
      refute_includes content, "## full.txt"
      assert_includes content, "## min.txt"
    end
  end
end
