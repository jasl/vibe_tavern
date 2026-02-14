# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Skills::FrontmatterTest < Minitest::Test
  def test_valid_frontmatter
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      ---

      # Body
    MD

    frontmatter, body = AgentCore::Resources::Skills::Frontmatter.parse(content)

    assert_equal "my-skill", frontmatter[:name]
    assert_equal "A test skill.", frontmatter[:description]
    assert_includes body, "# Body"
  end

  def test_frontmatter_with_metadata
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      metadata:
        author: "test"
        version: "1.0"
      ---
      Body here.
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content)

    assert_equal({ "author" => "test", "version" => "1.0" }, frontmatter[:metadata])
  end

  def test_frontmatter_with_allowed_tools
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      allowed_tools: tool-a tool-b
      ---
      Body here.
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content)

    assert_equal "tool-a tool-b", frontmatter[:allowed_tools]
  end

  def test_missing_opening_delimiter_strict
    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse("no frontmatter here", strict: true)
    end
  end

  def test_missing_opening_delimiter_lenient
    frontmatter, body = AgentCore::Resources::Skills::Frontmatter.parse("no frontmatter here", strict: false)

    assert_nil frontmatter
    assert_equal "no frontmatter here", body
  end

  def test_missing_closing_delimiter_strict
    content = "---\nname: test\n"

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_missing_name_strict
    content = <<~MD
      ---
      description: A skill.
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_missing_description_strict
    content = <<~MD
      ---
      name: my-skill
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_invalid_name_pattern_strict
    content = <<~MD
      ---
      name: My Skill
      description: A test skill.
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_name_must_match_directory
    content = <<~MD
      ---
      name: wrong-name
      description: A test skill.
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, expected_name: "correct-name", strict: true)
    end
  end

  def test_name_matches_directory
    content = <<~MD
      ---
      name: correct-name
      description: A test skill.
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content, expected_name: "correct-name")
    assert_equal "correct-name", frontmatter[:name]
  end

  def test_invalid_yaml_strict
    content = <<~MD
      ---
      name: [invalid yaml
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_metadata_must_be_hash_strict
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      metadata: "just a string"
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_metadata_values_must_be_strings_strict
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      metadata:
        count: 42
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    assert_equal "42", frontmatter[:metadata]["count"]
  end

  def test_metadata_values_coerced_lenient
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      metadata:
        count: 42
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content, strict: false)

    refute_nil frontmatter
    assert_equal "42", frontmatter[:metadata]["count"]
  end

  def test_description_max_length_strict
    long_desc = "a" * 1025
    content = "---\nname: my-skill\ndescription: #{long_desc}\n---\nBody"

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_valid_name_patterns
    assert AgentCore::Resources::Skills::Frontmatter.valid_name?("my-skill")
    assert AgentCore::Resources::Skills::Frontmatter.valid_name?("skill")
    assert AgentCore::Resources::Skills::Frontmatter.valid_name?("a-b-c")
    assert AgentCore::Resources::Skills::Frontmatter.valid_name?("skill123")
    assert AgentCore::Resources::Skills::Frontmatter.valid_name?("a")
  end

  def test_invalid_name_patterns
    refute AgentCore::Resources::Skills::Frontmatter.valid_name?("")
    refute AgentCore::Resources::Skills::Frontmatter.valid_name?("My Skill")
    refute AgentCore::Resources::Skills::Frontmatter.valid_name?("my_skill")
    refute AgentCore::Resources::Skills::Frontmatter.valid_name?("-leading")
    refute AgentCore::Resources::Skills::Frontmatter.valid_name?("trailing-")
    refute AgentCore::Resources::Skills::Frontmatter.valid_name?("a" * 65)
  end

  def test_hyphenated_keys_converted_to_underscores
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      allowed-tools: tool-a tool-b
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content)
    assert_equal "tool-a tool-b", frontmatter[:allowed_tools]
  end

  def test_compatibility_field
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      compatibility: Claude 3.5+
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content)
    assert_equal "Claude 3.5+", frontmatter[:compatibility]
  end

  def test_license_field
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      license: MIT
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content)
    assert_equal "MIT", frontmatter[:license]
  end

  def test_empty_frontmatter_yaml
    content = <<~MD
      ---
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_expected_name_from_path
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content, path: "/skills/my-skill/SKILL.md")
    assert_equal "my-skill", frontmatter[:name]
  end

  def test_expected_name_from_path_mismatch
    content = <<~MD
      ---
      name: wrong-name
      description: A test skill.
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, path: "/skills/correct-name/SKILL.md", strict: true)
    end
  end

  def test_rejects_unknown_fields_strict
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      extra-field: no
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_unknown_fields_lenient_returns_nil_frontmatter
    content = <<~MD
      ---
      name: my-skill
      description: A test skill.
      extra-field: no
      ---
      Body
    MD

    frontmatter, body = AgentCore::Resources::Skills::Frontmatter.parse(content, strict: false)
    assert_nil frontmatter
    assert_includes body, "Body"
  end

  def test_name_must_be_string_strict
    content = <<~MD
      ---
      name: 123
      description: A test skill.
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_description_must_be_string_strict
    content = <<~MD
      ---
      name: my-skill
      description: 123
      ---
      Body
    MD

    assert_raises(ArgumentError) do
      AgentCore::Resources::Skills::Frontmatter.parse(content, strict: true)
    end
  end

  def test_unicode_skill_name
    assert AgentCore::Resources::Skills::Frontmatter.valid_name?("数据分析")

    content = <<~MD
      ---
      name: 数据分析
      description: A test skill.
      ---
      Body
    MD

    frontmatter, = AgentCore::Resources::Skills::Frontmatter.parse(content, expected_name: "数据分析")
    assert_equal "数据分析", frontmatter[:name]
  end
end
