# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Skills::FileSystemStoreTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../../../fixtures/skills", __dir__)

  def setup
    @store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [FIXTURES_DIR])
  end

  def test_list_skills
    skills = @store.list_skills

    assert_instance_of Array, skills
    assert skills.size >= 2

    names = skills.map(&:name)
    assert_includes names, "example-skill"
    assert_includes names, "another-skill"
    assert_includes names, "lowercase-skill"
  end

  def test_list_skills_sorted_by_name
    skills = @store.list_skills
    names = skills.map(&:name)

    assert_equal names.sort, names
  end

  def test_list_skills_returns_metadata
    skills = @store.list_skills
    example = skills.find { |s| s.name == "example-skill" }

    assert_instance_of AgentCore::Resources::Skills::SkillMetadata, example
    assert_equal "example-skill", example.name
    assert_equal "An example skill for testing.", example.description
    assert_equal "MIT", example.license
    assert_includes example.location, "example-skill"
  end

  def test_list_skills_allowed_tools
    skills = @store.list_skills
    example = skills.find { |s| s.name == "example-skill" }

    assert_equal %w[tool-a tool-b], example.allowed_tools
  end

  def test_list_skills_metadata_field
    skills = @store.list_skills
    example = skills.find { |s| s.name == "example-skill" }

    assert_equal({ "author" => "test", "version" => "1.0" }, example.metadata)
  end

  def test_load_skill
    skill = @store.load_skill(name: "example-skill")

    assert_instance_of AgentCore::Resources::Skills::Skill, skill
    assert_equal "example-skill", skill.meta.name
    assert_includes skill.body_markdown, "# Example Skill"
    assert_includes skill.body_markdown, "Use this skill to test things."
    assert_equal false, skill.body_truncated
  end

  def test_load_skill_accepts_lowercase_skill_md
    skill = @store.load_skill(name: "lowercase-skill")

    assert_instance_of AgentCore::Resources::Skills::Skill, skill
    assert_equal "lowercase-skill", skill.meta.name
    assert_equal "MIT", skill.meta.license
    assert_includes skill.body_markdown, "verify that the store accepts"
  end

  def test_load_skill_files_index
    skill = @store.load_skill(name: "another-skill")

    assert_includes skill.files_index[:scripts], "scripts/setup.sh"
    assert_includes skill.files_index[:references], "references/guide.md"
    assert_includes skill.files_index[:assets], "assets/logo.txt"
  end

  def test_load_skill_unknown_raises
    assert_raises(ArgumentError) do
      @store.load_skill(name: "nonexistent-skill")
    end
  end

  def test_load_skill_max_bytes
    skill = @store.load_skill(name: "example-skill", max_bytes: 170)

    assert_equal true, skill.body_truncated
  end

  def test_read_skill_file
    content = @store.read_skill_file(
      name: "another-skill",
      rel_path: "scripts/setup.sh",
    )

    assert_includes content, "echo"
  end

  def test_read_skill_file_references
    content = @store.read_skill_file(
      name: "another-skill",
      rel_path: "references/guide.md",
    )

    assert_includes content, "# Guide"
  end

  def test_read_skill_file_bytes
    bytes = @store.read_skill_file_bytes(
      name: "another-skill",
      rel_path: "scripts/setup.sh",
    )

    assert_kind_of String, bytes
    assert_equal Encoding::BINARY, bytes.encoding
    assert_includes bytes, "echo"
  end

  def test_read_skill_file_unknown_skill_raises
    assert_raises(ArgumentError) do
      @store.read_skill_file(name: "nonexistent", rel_path: "scripts/a.sh")
    end
  end

  def test_read_skill_file_unknown_file_raises
    assert_raises(ArgumentError) do
      @store.read_skill_file(name: "another-skill", rel_path: "scripts/nonexistent.sh")
    end
  end

  def test_read_skill_file_invalid_path_absolute
    assert_raises(ArgumentError) do
      @store.read_skill_file(name: "another-skill", rel_path: "/etc/passwd")
    end
  end

  def test_read_skill_file_invalid_path_traversal
    assert_raises(ArgumentError) do
      @store.read_skill_file(name: "another-skill", rel_path: "scripts/../../../etc/passwd")
    end
  end

  def test_read_skill_file_invalid_top_dir
    assert_raises(ArgumentError) do
      @store.read_skill_file(name: "another-skill", rel_path: "other/file.txt")
    end
  end

  def test_strict_mode_nonexistent_dir
    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::FileSystemStore.new(dirs: ["/nonexistent/dir"], strict: true)
    end
  end

  def test_lenient_mode_nonexistent_dir
    store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: ["/nonexistent/dir"], strict: false)
    skills = store.list_skills

    assert_equal [], skills
  end

  def test_inherits_from_store
    assert_kind_of AgentCore::Resources::Skills::Store, @store
  end

  def test_empty_dirs
    store = AgentCore::Resources::Skills::FileSystemStore.new(dirs: [], strict: false)
    assert_equal [], store.list_skills
  end
end
