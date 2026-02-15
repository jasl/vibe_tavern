# frozen_string_literal: true

require "test_helper"

class AgentCoreContribDirectivesTest < ActiveSupport::TestCase
  test "Parser.parse_json unwraps code fences and xml-ish tags" do
    raw = "```json\n{\"assistant_text\":\"hi\",\"directives\":[]}\n```"
    parsed = AgentCore::Contrib::Directives::Parser.parse_json(raw)

    assert parsed[:ok]
    assert_equal "hi", parsed[:value].fetch("assistant_text")

    wrapped = "<json>{\"assistant_text\":\"yo\",\"directives\":[]}</json>"
    parsed2 = AgentCore::Contrib::Directives::Parser.parse_json(wrapped)

    assert parsed2[:ok]
    assert_equal "yo", parsed2[:value].fetch("assistant_text")
  end

  test "Parser.parse_json extracts the first JSON object when surrounded by text" do
    raw = "noise {\"assistant_text\":\"hi\",\"directives\":[]} trailing"
    parsed = AgentCore::Contrib::Directives::Parser.parse_json(raw)

    assert parsed[:ok]
    assert_equal [], parsed[:value].fetch("directives")
  end

  test "Parser.parse_json enforces max_bytes" do
    raw = "x" * 10
    parsed = AgentCore::Contrib::Directives::Parser.parse_json(raw, max_bytes: 1)

    refute parsed[:ok]
    assert_equal "TOO_LARGE", parsed[:code]
  end

  test "Validator.validate normalizes types, payload keys, and warnings" do
    envelope = {
      assistant_text: "hi",
      directives: [
        {
          type: "toast",
          payload: { message: "ok" },
        },
        { type: "", payload: {} },
        "nope",
      ],
    }

    validated =
      AgentCore::Contrib::Directives::Validator.validate(
        envelope,
        allowed_types: ["ui.toast"],
        type_aliases: { "toast" => "ui.toast" },
      )

    assert validated[:ok]

    value = validated[:value]
    assert_equal "hi", value.fetch("assistant_text")
    assert_equal 1, value.fetch("directives").length
    assert_equal "ui.toast", value.fetch("directives").first.fetch("type")
    assert_equal({ "message" => "ok" }, value.fetch("directives").first.fetch("payload"))
    assert validated.fetch(:warnings).any?
  end

  test "Validator.normalize_patch_ops canonicalizes op aliases and validates path prefixes" do
    normalized =
      AgentCore::Contrib::Directives::Validator.normalize_patch_ops(
        {
          op: "add",
          path: "title",
          value: "Hello",
        },
      )

    assert normalized[:ok]
    op = normalized.fetch(:ops).first
    assert_equal "set", op.fetch("op")
    assert_equal "/draft/title", op.fetch("path")
    assert_equal "Hello", op.fetch("value")

    invalid =
      AgentCore::Contrib::Directives::Validator.normalize_patch_ops(
        { op: "set", path: "/etc/passwd", value: "x" },
      )
    refute invalid[:ok]
    assert_equal "INVALID_PATCH_PATH", invalid[:code]
  end
end
