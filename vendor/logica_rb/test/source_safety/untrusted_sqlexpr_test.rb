# frozen_string_literal: true

require "test_helper"

class UntrustedSqlExprTest < Minitest::Test
  def parse_rules(source)
    LogicaRb::Parser.parse_file(source.to_s, import_root: "")["rule"]
  end

  def test_untrusted_source_rejects_sqlexpr_by_default
    source = <<~LOGICA
      @Engine("sqlite");

      Evil() = SqlExpr("1", {x: 1});
    LOGICA

    err =
      assert_raises(LogicaRb::SourceSafety::Violation) do
        LogicaRb::SourceSafety::Validator.validate!(parse_rules(source), engine: "sqlite", trust: :untrusted, capabilities: [])
      end

    assert_match(/SqlExpr/, err.message)
    assert_match(/sql_expr/, err.message)
  end

  def test_untrusted_source_allows_sqlexpr_with_capability
    source = <<~LOGICA
      @Engine("sqlite");

      Ok() = SqlExpr("1", {x: 1});
    LOGICA

    LogicaRb::SourceSafety::Validator.validate!(
      parse_rules(source),
      engine: "sqlite",
      trust: :untrusted,
      capabilities: [:sql_expr]
    )
  end
end
