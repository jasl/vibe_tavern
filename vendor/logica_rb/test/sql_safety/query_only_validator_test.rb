# frozen_string_literal: true

require "test_helper"

class QueryOnlyValidatorTest < Minitest::Test
  def test_rejects_empty_sql
    err = assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!(" \n\t")
    end

    assert_equal :empty_sql, err.reason
  end

  def test_allows_select_with_and_values
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1\n")
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("WITH t AS (SELECT 1 AS x) SELECT x FROM t\n")
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("VALUES (1)\n")
  end

  def test_allows_single_trailing_semicolon
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1;\n")
  end

  def test_rejects_multiple_statements
    err = assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1; SELECT 2", engine: "sqlite")
    end

    assert_match(/Multiple SQL statements/i, err.message)
  end

  def test_rejects_dml_and_ddl_keywords
    %w[INSERT UPDATE DELETE MERGE CREATE DROP ALTER TRUNCATE GRANT REVOKE].each do |kw|
      assert_raises(LogicaRb::SqlSafety::Violation, "expected #{kw} to be rejected") do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 #{kw} 2", engine: "sqlite")
      end
    end
  end

  def test_rejects_transactions_and_session_keywords
    %w[BEGIN COMMIT ROLLBACK SET RESET].each do |kw|
      assert_raises(LogicaRb::SqlSafety::Violation, "expected #{kw} to be rejected") do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 #{kw} 2", engine: "sqlite")
      end
    end
  end

  def test_engine_specific_keywords
    %w[ATTACH DETACH].each do |kw|
      assert_raises(LogicaRb::SqlSafety::Violation, "expected #{kw} to be rejected") do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 #{kw} 2", engine: "sqlite")
      end
    end

    assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 PRAGMA 2", engine: "sqlite")
    end

    %w[COPY DO CALL].each do |kw|
      assert_raises(LogicaRb::SqlSafety::Violation, "expected #{kw} to be rejected") do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 #{kw} 2", engine: "psql")
      end
    end
  end

  def test_rejects_select_into_for_psql
    assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 INTO new_table", engine: "psql")
    end
  end

  def test_explain_is_opt_in
    assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("EXPLAIN SELECT 1", engine: "sqlite")
    end

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("EXPLAIN SELECT 1", engine: "sqlite", allow_explain: true)
  end

  def test_rejects_dangerous_functions_sqlite
    assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT load_extension('x')", engine: "sqlite")
    end
  end

  def test_rejects_dangerous_functions_psql
    assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT pg_read_file('/etc/passwd')", engine: "psql")
    end

    assert_raises(LogicaRb::SqlSafety::Violation) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT set_config('statement_timeout','0',true)", engine: "psql")
    end
  end

  def test_rejects_additional_admin_and_dos_functions_psql
    %w[
      pg_sleep_for pg_sleep_until
      pg_cancel_backend pg_terminate_backend pg_reload_conf
      dblink dblink_connect_u
    ].each do |func|
      assert_raises(LogicaRb::SqlSafety::Violation, "expected #{func} to be rejected") do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT #{func}()", engine: "psql")
      end
    end

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT pg_catalog.pg_sleep_for('1 second')", engine: "psql")
      end
    assert_equal :forbidden_function, err.reason

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!(%(SELECT "pg_reload_conf"()), engine: "psql")
      end
    assert_equal :forbidden_function, err.reason
  end

  def test_rejects_quoted_dangerous_functions
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT \"pg_read_file\"('/etc/passwd')", engine: "psql")
      end
    assert_equal :forbidden_function, err.reason

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        sql = %q(SELECT "pg_catalog"."pg_read_file"('/etc/passwd'))
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!(sql, engine: "psql")
      end
    assert_equal :forbidden_function, err.reason

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT \"load_extension\"('x')", engine: "sqlite")
      end
    assert_equal :forbidden_function, err.reason

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT `load_extension`('x')", engine: "sqlite")
      end
    assert_equal :forbidden_function, err.reason

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT [load_extension]('x')", engine: "sqlite")
      end
    assert_equal :forbidden_function, err.reason
  end

  def test_ignores_strings_and_comments
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT 'DROP TABLE users; INSERT INTO x VALUES (1)' AS message\n",
      engine: "sqlite"
    )

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT 1 -- DROP TABLE users; INSERT INTO x VALUES (1)\n",
      engine: "sqlite"
    )

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT 'pg_read_file(/etc/passwd)' AS msg\n",
      engine: "psql"
    )

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT 'pg_reload_conf()' AS msg\n",
      engine: "psql"
    )

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT 1 /* load_extension('x') */\n",
      engine: "sqlite"
    )
  end

  def test_ignores_dollar_quoted_strings_psql
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT $tag$; DROP TABLE users; --$tag$ AS s\n",
      engine: "psql"
    )
  end

  def test_unterminated_dollar_quoted_strings_do_not_crash
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT $tag$; DROP TABLE users; -- no close\n",
      engine: "psql"
    )
  end

  def test_nested_block_comments_do_not_trigger_semicolon_detection
    sql = <<~SQL
      SELECT 1 /* outer ; /* inner ; */ still in outer ; */ AS x
    SQL

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(sql, engine: "sqlite")
  end

  def test_custom_forbidden_functions_list_is_supported
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT my_evil(1)", engine: "sqlite", forbidden_functions: ["my_evil"])
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/my_evil/i, err.message)
  end

  def test_quoted_identifiers_with_escapes_are_handled_in_function_scan
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!(%(SELECT "a""b"(1)), engine: "sqlite", forbidden_functions: ['a"b'])
      end
    assert_equal :forbidden_function, err.reason

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT `a``b`(1)", engine: "sqlite", forbidden_functions: ["a`b"])
      end
    assert_equal :forbidden_function, err.reason

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT [a]]b](1)", engine: "sqlite", forbidden_functions: ["a]b"])
      end
    assert_equal :forbidden_function, err.reason
  end

  def test_fuzz_does_not_crash
    rng = Random.new(42)
    atoms = [
      " ", "\n", "\t",
      "'", "\"", "`", "[", "]", "(", ")", ";", ".", ",",
      "--", "/*", "*/",
      "$", "$tag$",
      "A", "Z", "a", "z", "0", "9", "_",
      "雪", "€", "β",
    ].freeze

    250.times do
      fragment = Array.new(rng.rand(0..120)) { atoms.sample(random: rng) }.join
      sql = "SELECT #{fragment}"

      begin
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!(sql, engine: "psql", allow_explain: true)
      rescue LogicaRb::SqlSafety::Violation
        # expected sometimes
      end
    end
  end
end
