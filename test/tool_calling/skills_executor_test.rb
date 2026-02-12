# frozen_string_literal: true

require_relative "test_helper"

require "fileutils"
require "tmpdir"

class SkillsExecutorTest < Minitest::Test
  def write_skill(root, name:, description: "Test skill", body: "Body")
    skill_dir = File.join(root, name)
    FileUtils.mkdir_p(skill_dir)

    File.write(
      File.join(skill_dir, "SKILL.md"),
      <<~MD,
        ---
        name: #{name}
        description: #{description}
        ---
        #{body}
      MD
    )

    skill_dir
  end

  def test_skills_tools_list_load_and_read_file
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      skill_dir = write_skill(skills_root, name: "foo", description: "Foo skill", body: "Hello from foo")
      FileUtils.mkdir_p(File.join(skill_dir, "references"))
      File.write(File.join(skill_dir, "references", "x.md"), "ref-x")

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)
      executor = TavernKit::VibeTavern::ToolCalling::Executors::SkillsExecutor.new(store: store, max_bytes: 200_000)

      list = executor.call(name: "skills_list", args: {})
      assert_equal true, list.fetch(:ok)
      assert_equal [{ name: "foo", description: "Foo skill" }], list.fetch(:data).fetch(:skills)

      loaded = executor.call(name: "skills_load", args: { "name" => "foo" })
      assert_equal true, loaded.fetch(:ok)
      assert_equal "foo", loaded.fetch(:data).fetch(:name)
      assert_includes loaded.fetch(:data).fetch(:body_markdown), "Hello from foo"
      assert_includes loaded.fetch(:data).fetch(:files), "references/x.md"

      file = executor.call(name: "skills_read_file", args: { "name" => "foo", "path" => "references/x.md" })
      assert_equal true, file.fetch(:ok)
      assert_equal "references/x.md", file.fetch(:data).fetch(:path)
      assert_equal "ref-x", file.fetch(:data).fetch(:content)
    end
  end

  def test_skills_run_script_is_not_implemented
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      write_skill(skills_root, name: "foo")
      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)
      executor = TavernKit::VibeTavern::ToolCalling::Executors::SkillsExecutor.new(store: store, max_bytes: 200_000)

      result = executor.call(name: "skills_run_script", args: { "name" => "foo", "script" => "scripts/run.rb" })
      assert_equal false, result.fetch(:ok)
      assert_equal "NOT_IMPLEMENTED", result.fetch(:errors).first.fetch(:code)
    end
  end

  def test_skills_tools_map_common_errors
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      write_skill(skills_root, name: "foo")
      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)
      executor = TavernKit::VibeTavern::ToolCalling::Executors::SkillsExecutor.new(store: store, max_bytes: 200_000)

      missing = executor.call(name: "skills_load", args: { "name" => "nope" })
      assert_equal false, missing.fetch(:ok)
      assert_equal "SKILL_NOT_FOUND", missing.fetch(:errors).first.fetch(:code)

      invalid = executor.call(name: "skills_read_file", args: { "name" => "foo", "path" => "../x" })
      assert_equal false, invalid.fetch(:ok)
      assert_equal "INVALID_PATH", invalid.fetch(:errors).first.fetch(:code)
    end
  end
end
