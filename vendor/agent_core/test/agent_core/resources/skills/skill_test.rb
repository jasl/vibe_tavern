# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Skills::SkillTest < Minitest::Test
  def setup
    @meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test-skill",
      description: "A test skill",
      location: "/path/to/skill",
    )
  end

  def test_basic_creation
    skill = AgentCore::Resources::Skills::Skill.new(
      meta: @meta,
      body_markdown: "# Hello",
    )

    assert_same @meta, skill.meta
    assert_equal "# Hello", skill.body_markdown
    assert_equal false, skill.body_truncated
    assert_equal({ scripts: [], references: [], assets: [] }, skill.files_index)
  end

  def test_body_truncated
    skill = AgentCore::Resources::Skills::Skill.new(
      meta: @meta,
      body_markdown: "# Hello",
      body_truncated: true,
    )

    assert_equal true, skill.body_truncated
  end

  def test_body_truncated_only_true_for_true
    skill = AgentCore::Resources::Skills::Skill.new(
      meta: @meta,
      body_markdown: "# Hello",
      body_truncated: "yes",
    )

    assert_equal false, skill.body_truncated
  end

  def test_files_index
    skill = AgentCore::Resources::Skills::Skill.new(
      meta: @meta,
      body_markdown: "# Hello",
      files_index: {
        scripts: ["scripts/setup.sh", "scripts/build.sh"],
        references: ["references/guide.md"],
        assets: [],
      },
    )

    assert_equal ["scripts/build.sh", "scripts/setup.sh"], skill.files_index[:scripts]
    assert_equal ["references/guide.md"], skill.files_index[:references]
    assert_equal [], skill.files_index[:assets]
  end

  def test_files_index_sorts
    skill = AgentCore::Resources::Skills::Skill.new(
      meta: @meta,
      body_markdown: "# Hello",
      files_index: {
        scripts: ["scripts/z.sh", "scripts/a.sh"],
      },
    )

    assert_equal ["scripts/a.sh", "scripts/z.sh"], skill.files_index[:scripts]
  end

  def test_files_index_strips_blanks
    skill = AgentCore::Resources::Skills::Skill.new(
      meta: @meta,
      body_markdown: "# Hello",
      files_index: {
        scripts: ["scripts/a.sh", "", "  "],
      },
    )

    assert_equal ["scripts/a.sh"], skill.files_index[:scripts]
  end

  def test_files_index_defaults_empty
    skill = AgentCore::Resources::Skills::Skill.new(
      meta: @meta,
      body_markdown: "# Hello",
      files_index: nil,
    )

    assert_equal({ scripts: [], references: [], assets: [] }, skill.files_index)
  end

  def test_meta_must_be_skill_metadata
    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Skill.new(
        meta: { name: "test" },
        body_markdown: "# Hello",
      )
    end
  end

  def test_data_define_frozen
    skill = AgentCore::Resources::Skills::Skill.new(meta: @meta, body_markdown: "# Hello")
    assert skill.frozen?
  end

  def test_body_markdown_coerced_to_string
    skill = AgentCore::Resources::Skills::Skill.new(meta: @meta, body_markdown: nil)
    assert_equal "", skill.body_markdown
  end
end
