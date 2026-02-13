# frozen_string_literal: true

require_relative "test_helper"

class SkillsFrontmatterTest < Minitest::Test
  def test_parse_valid_frontmatter
    content = <<~MD
      ---
      name: foo
      description: Foo skill
      metadata:
        author: me
      allowed_tools:
        - skills_list
      ---
      # Hello

      Body text.
    MD

    frontmatter, body = TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content, expected_name: "foo", strict: true)

    assert_equal "foo", frontmatter.fetch(:name)
    assert_equal "Foo skill", frontmatter.fetch(:description)
    assert_equal({ "author" => "me" }, frontmatter.fetch(:metadata))
    assert_includes body, "Body text."
  end

  def test_parse_rejects_missing_opening_delimiter
    content = <<~MD
      name: foo
      description: x
      ---
      Body
    MD

    error = assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content) }
    assert_includes error.message, "frontmatter must start"
  end

  def test_parse_rejects_missing_closing_delimiter
    content = <<~MD
      ---
      name: foo
      description: x
      Body
    MD

    error = assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content) }
    assert_includes error.message, "missing closing"
  end

  def test_parse_rejects_non_mapping_yaml
    content = <<~MD
      ---
      - 1
      - 2
      ---
      Body
    MD

    error = assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content) }
    assert_includes error.message, "YAML mapping"
  end

  def test_parse_rejects_missing_required_fields
    content = <<~MD
      ---
      name: foo
      ---
      Body
    MD

    error = assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content) }
    assert_includes error.message, "description"
  end

  def test_parse_rejects_invalid_names
    invalid = [
      "A",
      "foo--bar",
      "-foo",
      "foo-",
      ("a" * 65),
    ]

    invalid.each do |name|
      content = <<~MD
        ---
        name: #{name}
        description: x
        ---
        Body
      MD

      error = assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content) }
      assert_includes error.message, "invalid skill name"
    end
  end

  def test_parse_rejects_name_that_does_not_match_parent_dir
    content = <<~MD
      ---
      name: bar
      description: x
      ---
      Body
    MD

    error = assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content, expected_name: "foo") }
    assert_includes error.message, "must match directory name"
  end

  def test_parse_returns_nil_frontmatter_in_non_strict_mode
    content = <<~MD
      ---
      name: A
      description: x
      ---
      Body
    MD

    frontmatter, body = TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content, strict: false)
    assert_nil frontmatter
    assert_includes body, "Body"
  end

  def test_parse_rejects_non_hash_metadata
    content = <<~MD
      ---
      name: foo
      description: x
      metadata: not-a-hash
      ---
      Body
    MD

    assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content, expected_name: "foo", strict: true) }

    frontmatter, body = TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content, expected_name: "foo", strict: false)
    assert_nil frontmatter
    assert_includes body, "Body"
  end

  def test_parse_accepts_allowed_tools_dash_key_and_skill_metadata_normalizes
    content = <<~MD
      ---
      name: foo
      description: Foo skill
      allowed-tools: skills_list skills_load
      metadata:
        author: me
      ---
      Body
    MD

    frontmatter, =
      TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(
        content,
        expected_name: "foo",
        strict: true,
      )

    meta =
      TavernKit::VibeTavern::Tools::Skills::SkillMetadata.new(
        name: frontmatter.fetch(:name),
        description: frontmatter.fetch(:description),
        location: "/tmp/foo",
        metadata: frontmatter.fetch(:metadata),
        allowed_tools: frontmatter.fetch(:allowed_tools),
      )

    assert_equal ["skills_list", "skills_load"], meta.allowed_tools
    assert_equal "skills_list skills_load", meta.allowed_tools_raw
  end

  def test_parse_rejects_non_string_metadata_values_in_strict_mode
    content = <<~MD
      ---
      name: foo
      description: Foo skill
      metadata:
        author: me
        version: 1
      ---
      Body
    MD

    error = assert_raises(ArgumentError) { TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(content, strict: true) }
    assert_includes error.message, "frontmatter.metadata"

    frontmatter, =
      TavernKit::VibeTavern::Tools::Skills::Frontmatter.parse(
        content,
        strict: false,
      )
    refute_nil frontmatter
    assert_equal({ "author" => "me", "version" => "1" }, frontmatter.fetch(:metadata))
  end
end
