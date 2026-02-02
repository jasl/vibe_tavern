# frozen_string_literal: true

require "test_helper"

class FunctionAllowlistValidatorTest < Minitest::Test
  def validate!(sql, **opts)
    LogicaRb::SqlSafety::FunctionAllowlistValidator.validate!(sql, **opts)
  end

  def test_minimal_allows_basic_aggregates
    allowed = LogicaRb::AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS

    used =
      validate!(
        "SELECT SUM(x), COUNT(*), AVG(x), MIN(x), MAX(x) FROM t",
        engine: "sqlite",
        allowed_functions: allowed
      )

    assert_equal Set.new(%w[sum count avg min max]), used
  end

  def test_minimal_plus_allows_cast_coalesce_nullif
    allowed = LogicaRb::AccessPolicy::RAILS_MINIMAL_PLUS_ALLOWED_FUNCTIONS

    used =
      validate!(
        "SELECT CAST(x AS TEXT), COALESCE(x, 1), NULLIF(x, 0) FROM t",
        engine: "sqlite",
        allowed_functions: allowed
      )

    assert_equal Set.new(%w[cast coalesce nullif]), used
  end

  def test_minimal_rejects_cast_coalesce_nullif
    allowed = LogicaRb::AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS

    %w[cast coalesce nullif].each do |func|
      err =
        assert_raises(LogicaRb::SqlSafety::Violation) do
          validate!("SELECT #{func}(x) FROM t", engine: "sqlite", allowed_functions: allowed)
        end

      assert_equal :function_not_allowed, err.reason
      assert_equal func, err.details&.dig(:function)
    end
  end

  def test_rejects_non_allowlisted_function
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!("SELECT my_evil(1)", engine: "sqlite", allowed_functions: ["coalesce"])
      end

    assert_equal :function_not_allowed, err.reason
    assert_equal "my_evil", err.details&.dig(:function)
  end

  def test_ignores_strings_and_comments
    sql = <<~SQL
      SELECT 'pg_read_file(' AS s, COALESCE(NULL, 1) AS x -- pg_read_file(1)
    SQL

    used = validate!(sql, engine: "psql", allowed_functions: ["coalesce"])
    assert_equal Set.new(["coalesce"]), used
  end

  def test_handles_escaped_quotes_and_semicolons_inside_strings
    sql = "SELECT 'abc''; DROP TABLE users; --' AS s, COALESCE('a', 'b') AS x"

    used = validate!(sql, engine: "psql", allowed_functions: ["coalesce"])
    assert_equal Set.new(["coalesce"]), used
  end

  def test_extracts_schema_qualified_function_name_as_unqualified
    used =
      validate!(
        %q(SELECT "pg_catalog"."pg_read_file"('/etc/passwd')),
        engine: "psql",
        allowed_functions: nil
      )

    assert_equal Set.new(["pg_read_file"]), used
  end

  def test_does_not_treat_in_as_a_function
    used = validate!("SELECT 1 WHERE 1 IN (SELECT 1)", engine: "psql", allowed_functions: [])
    assert_equal Set.new, used
  end

  def test_does_not_treat_exists_over_filter_as_functions
    allowed = LogicaRb::AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS

    used = validate!("SELECT 1 WHERE EXISTS(SELECT 1)", engine: "psql", allowed_functions: [])
    assert_equal Set.new, used

    used = validate!("SELECT COUNT(*) OVER (PARTITION BY x) FROM t", engine: "psql", allowed_functions: allowed)
    assert_equal Set.new(["count"]), used

    used = validate!("SELECT COUNT(*) FILTER (WHERE x > 0) FROM t", engine: "psql", allowed_functions: allowed)
    assert_equal Set.new(["count"]), used
  end

  def test_rejects_common_non_minimal_functions
    allowed = LogicaRb::AccessPolicy::RAILS_MINIMAL_PLUS_ALLOWED_FUNCTIONS

    %w[lower upper strftime date_trunc].each do |func|
      err =
        assert_raises(LogicaRb::SqlSafety::Violation) do
          validate!("SELECT #{func}(x) FROM t", engine: "psql", allowed_functions: allowed)
        end

      assert_equal :function_not_allowed, err.reason
      assert_equal func, err.details&.dig(:function)
    end
  end

  def test_quoted_identifiers_cannot_bypass_allowlist_or_denylist
    minimal = LogicaRb::AccessPolicy::RAILS_MINIMAL_ALLOWED_FUNCTIONS

    used = validate!(%(SELECT "sum"(x) FROM t), engine: "sqlite", allowed_functions: minimal)
    assert_equal Set.new(["sum"]), used

    forbidden_psql = LogicaRb::SqlSafety::QueryOnlyValidator.forbidden_functions_for_engine("psql")

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          %(SELECT "pg_read_file"('/etc/passwd')),
          engine: "psql",
          allowed_functions: Set.new(["pg_read_file"]),
          forbidden_functions: forbidden_psql
        )
      end

    assert_equal :forbidden_function, err.reason
    assert_equal "pg_read_file", err.details

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          %(SELECT pg_cancel_backend(123)),
          engine: "psql",
          allowed_functions: Set.new(["pg_cancel_backend"]),
          forbidden_functions: forbidden_psql
        )
      end

    assert_equal :forbidden_function, err.reason
    assert_equal "pg_cancel_backend", err.details
  end
end
