# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Skills::SkillMetadataTest < Minitest::Test
  def test_basic_creation
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "my-skill",
      description: "A test skill",
      location: "/path/to/skill",
    )

    assert_equal "my-skill", meta.name
    assert_equal "A test skill", meta.description
    assert_equal "/path/to/skill", meta.location
    assert_nil meta.license
    assert_nil meta.compatibility
    assert_equal({}, meta.metadata)
    assert_equal [], meta.allowed_tools
    assert_nil meta.allowed_tools_raw
  end

  def test_full_creation
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "my-skill",
      description: "A test skill",
      location: "/path/to/skill",
      license: "MIT",
      compatibility: "Claude 3.5+",
      metadata: { "author" => "test", "version" => "1.0" },
      allowed_tools: %w[tool-a tool-b],
    )

    assert_equal "MIT", meta.license
    assert_equal "Claude 3.5+", meta.compatibility
    assert_equal({ "author" => "test", "version" => "1.0" }, meta.metadata)
    assert_equal %w[tool-a tool-b], meta.allowed_tools
  end

  def test_allowed_tools_from_string
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
      allowed_tools: "tool-a  tool-b  tool-c",
    )

    assert_equal %w[tool-a tool-b tool-c], meta.allowed_tools
  end

  def test_allowed_tools_deduplication
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
      allowed_tools: %w[tool-a tool-b tool-a],
    )

    assert_equal %w[tool-a tool-b], meta.allowed_tools
  end

  def test_allowed_tools_strips_blanks
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
      allowed_tools: ["tool-a", "", "  ", "tool-b"],
    )

    assert_equal %w[tool-a tool-b], meta.allowed_tools
  end

  def test_metadata_normalization
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
      metadata: { author: "test", version: 42 },
    )

    assert_equal({ "author" => "test", "version" => "42" }, meta.metadata)
  end

  def test_metadata_skips_blank_keys
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
      metadata: { "" => "empty", "  " => "blank", "valid" => "ok" },
    )

    assert_equal({ "valid" => "ok" }, meta.metadata)
  end

  def test_blank_license_becomes_nil
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
      license: "  ",
    )

    assert_nil meta.license
  end

  def test_blank_compatibility_becomes_nil
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
      compatibility: "",
    )

    assert_nil meta.compatibility
  end

  def test_data_define_frozen
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: "test",
      description: "test",
      location: "/test",
    )

    assert meta.frozen?
  end

  def test_data_define_equality
    a = AgentCore::Resources::Skills::SkillMetadata.new(name: "test", description: "d", location: "/p")
    b = AgentCore::Resources::Skills::SkillMetadata.new(name: "test", description: "d", location: "/p")

    assert_equal a, b
  end

  def test_name_coerced_to_string
    meta = AgentCore::Resources::Skills::SkillMetadata.new(
      name: :my_skill,
      description: "test",
      location: "/test",
    )

    assert_equal "my_skill", meta.name
  end
end
