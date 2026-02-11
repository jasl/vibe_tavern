# frozen_string_literal: true

require_relative "test_helper"

require_relative "../../lib/tavern_kit/vibe_tavern/directives/validator"

class DirectivesValidatorTest < Minitest::Test
  def test_validate_accepts_assistant_text_key_variants
    envelope = {
      "assistant‒text" => "ok",
      "directives" => [
        { "type" => "ui.show_form", "payload" => { "form_id" => "character_form_v1" } },
      ],
    }

    result =
      TavernKit::VibeTavern::Directives::Validator.validate(
        envelope,
        allowed_types: ["ui.show_form"],
      )

    assert_equal true, result[:ok]
    assert_equal "ok", result[:value].fetch("assistant_text")
  end

  def test_validate_canonicalizes_superficial_type_variants_via_allowlist
    envelope = {
      "assistant_text" => "ok",
      "directives" => [
        { "type" => "ui_show_form", "payload" => { "form_id" => "character_form_v1" } },
      ],
    }

    result =
      TavernKit::VibeTavern::Directives::Validator.validate(
        envelope,
        allowed_types: ["ui.show_form"],
      )

    assert_equal true, result[:ok]
    assert_equal "ui.show_form", result[:value].fetch("directives")[0].fetch("type")
  end

  def test_validate_drops_unknown_directives_and_reports_warning
    envelope = {
      "assistant_text" => "ok",
      "directives" => [
        { "type" => "ui.unknown", "payload" => {} },
      ],
    }

    result =
      TavernKit::VibeTavern::Directives::Validator.validate(
        envelope,
        allowed_types: ["ui.show_form"],
      )

    assert_equal true, result[:ok]
    assert_empty result[:value].fetch("directives")
    assert_equal "UNKNOWN_DIRECTIVE_TYPE", result[:warnings][0].fetch(:code)
  end

  def test_validate_patch_ops_rejects_invalid_path_prefix
    ops = [
      { "op" => "set", "path" => "/facts/foo", "value" => "bar" },
    ]

    err = TavernKit::VibeTavern::Directives::Validator.validate_patch_ops(ops)
    assert_equal "INVALID_PATCH_PATH", err.fetch(:code)
  end

  def test_validate_patch_ops_rejects_unknown_op
    ops = [
      { "op" => "rename", "path" => "/draft/foo", "value" => "bar" },
    ]

    err = TavernKit::VibeTavern::Directives::Validator.validate_patch_ops(ops)
    assert_equal "INVALID_PATCH_OP", err.fetch(:code)
  end

  def test_normalize_patch_ops_canonicalizes_common_json_patch_ops
    ops = [
      { "op" => "replace", "path" => "/draft/foo", "value" => "bar" },
      { "op" => "remove", "path" => "/draft/old" },
    ]

    result = TavernKit::VibeTavern::Directives::Validator.normalize_patch_ops(ops)
    assert_equal true, result.fetch(:ok)
    assert_equal "set", result.fetch(:ops)[0].fetch("op")
    assert_equal "delete", result.fetch(:ops)[1].fetch("op")
  end

  def test_normalize_patch_ops_infers_op_when_missing
    ops = [
      { "path" => "/draft/foo", "value" => "bar" },
      { "path" => "/draft/old" },
    ]

    result = TavernKit::VibeTavern::Directives::Validator.normalize_patch_ops(ops)
    assert_equal true, result.fetch(:ok)
    assert_equal "set", result.fetch(:ops)[0].fetch("op")
    assert_equal "delete", result.fetch(:ops)[1].fetch("op")
  end

  def test_normalize_patch_ops_normalizes_relative_paths
    ops = [
      { "op" => "set", "path" => "foo", "value" => "bar" },
      { "op" => "delete", "path" => "draft/old" },
      { "op" => "set", "path" => "`/draft/quoted`", "value" => "ok" },
    ]

    result = TavernKit::VibeTavern::Directives::Validator.normalize_patch_ops(ops)
    assert_equal true, result.fetch(:ok)
    assert_equal "/draft/foo", result.fetch(:ops)[0].fetch("path")
    assert_equal "/draft/old", result.fetch(:ops)[1].fetch("path")
    assert_equal "/draft/quoted", result.fetch(:ops)[2].fetch("path")
  end
end
