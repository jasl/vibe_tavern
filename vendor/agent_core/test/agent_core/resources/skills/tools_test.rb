# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Skills::ToolsTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../../../fixtures/skills", __dir__)

  def setup
    @store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [FIXTURES_DIR])
    @tools = AgentCore::Resources::Skills::Tools.build(store: @store)
  end

  def test_build_returns_three_tools
    names = @tools.map(&:name)
    assert_includes names, "skills.list"
    assert_includes names, "skills.load"
    assert_includes names, "skills.read_file"
  end

  def test_skills_list_returns_json
    tool = @tools.find { |t| t.name == "skills.list" }
    result = tool.call({})

    require "json"
    json = JSON.parse(result.text)
    names = json.fetch("skills").map { |s| s.fetch("name") }
    assert_includes names, "example-skill"
    assert_includes names, "another-skill"
  end

  def test_skills_load_returns_body_and_files_index
    tool = @tools.find { |t| t.name == "skills.load" }
    result = tool.call({ "name" => "example-skill" })

    require "json"
    json = JSON.parse(result.text)
    assert_equal "example-skill", json.dig("meta", "name")
    assert_includes json.fetch("body_markdown"), "# Example Skill"
    assert_equal false, json.fetch("body_truncated")
    assert json.fetch("files_index").is_a?(Hash)
  end

  def test_skills_read_file_returns_text_for_markdown
    tool = @tools.find { |t| t.name == "skills.read_file" }
    result = tool.call({ "name" => "another-skill", "rel_path" => "references/guide.md" })

    refute result.error?
    assert_includes result.text, "# Guide"
  end

  def test_skills_read_file_returns_base64_for_binary
    require "fileutils"
    require "tmpdir"
    require "base64"

    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      skill_dir = File.join(skills_root, "bin-skill")
      FileUtils.mkdir_p(skill_dir)
      File.write(
        File.join(skill_dir, "SKILL.md"),
        <<~MD,
          ---
          name: bin-skill
          description: Binary skill
          ---
          # Bin Skill
        MD
      )

      FileUtils.mkdir_p(File.join(skill_dir, "assets"))
      bytes = "\x00\xFFpng".b
      File.binwrite(File.join(skill_dir, "assets", "logo.png"), bytes)

      store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [skills_root])
      tools = AgentCore::Resources::Skills::Tools.build(store: store)
      read = tools.find { |t| t.name == "skills.read_file" }

      result = read.call({ "name" => "bin-skill", "rel_path" => "assets/logo.png" })

      assert result.has_non_text_content?
      block = result.content.first
      assert_equal :image, block.fetch(:type)
      assert_equal :base64, block.fetch(:source_type)
      assert_equal "image/png", block.fetch(:media_type)
      assert_equal Base64.strict_encode64(bytes), block.fetch(:data)
    end
  end
end
