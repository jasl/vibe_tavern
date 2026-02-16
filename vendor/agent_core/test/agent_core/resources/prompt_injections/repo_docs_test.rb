# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class AgentCore::Resources::PromptInjections::Sources::RepoDocsTest < Minitest::Test
  def test_discovers_repo_root_with_git_directory_and_orders_root_to_cwd
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, ".git"))

      File.write(File.join(dir, "AGENTS.md"), "ROOT")

      sub = File.join(dir, "sub")
      Dir.mkdir(sub)
      File.write(File.join(sub, "AGENTS.md"), "SUB")

      source = AgentCore::Resources::PromptInjections::Sources::RepoDocs.new
      ctx = AgentCore::ExecutionContext.from({ cwd: sub })

      items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)
      assert_equal 1, items.size

      content = items.first.content
      assert_includes content, "<user_instructions>"
      assert_includes content, "</user_instructions>"
      assert_includes content, "## AGENTS.md"
      assert_includes content, "## sub/AGENTS.md"

      idx_root = content.index("ROOT")
      idx_sub = content.index("SUB")
      assert idx_root && idx_sub
      assert_operator idx_root, :<, idx_sub
    end
  end

  def test_discovers_repo_root_with_git_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".git"), "gitdir: .git/worktrees/x\n")
      File.write(File.join(dir, "AGENTS.md"), "ROOT")

      source = AgentCore::Resources::PromptInjections::Sources::RepoDocs.new
      ctx = AgentCore::ExecutionContext.from({ cwd: dir })

      items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)
      assert_equal 1, items.size
      assert_includes items.first.content, "ROOT"
    end
  end

  def test_max_total_bytes_truncates_body_but_preserves_wrapper
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, ".git"))
      File.write(File.join(dir, "AGENTS.md"), "A" * 200)

      source = AgentCore::Resources::PromptInjections::Sources::RepoDocs.new(max_total_bytes: 40)
      ctx = AgentCore::ExecutionContext.from({ cwd: dir })

      items = source.items(agent: nil, user_message: "u", execution_context: ctx, prompt_mode: :full)
      assert_equal 1, items.size

      content = items.first.content
      assert_includes content, "<user_instructions>"
      assert_includes content, "</user_instructions>"
      assert_includes content, "\n...\n"
    end
  end
end
