# frozen_string_literal: true

require "test_helper"

class ForbiddenFunctionsValidatorTest < Minitest::Test
  def validate!(sql, **opts)
    LogicaRb::SqlSafety::ForbiddenFunctionsValidator.validate!(sql, **opts)
  end

  def test_supports_custom_forbidden_functions
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!("SELECT my_evil(1)", engine: "sqlite", forbidden_functions: ["my_evil"])
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/my_evil/i, err.message)
  end

  def test_rejects_admin_and_dos_functions_psql
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!("SELECT pg_cancel_backend(123)", engine: "psql")
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/pg_cancel_backend/i, err.message)
  end

  def test_rejects_dangerous_sqlite_functions
    %w[load_extension readfile writefile].each do |func|
      err =
        assert_raises(LogicaRb::SqlSafety::Violation, "expected #{func} to be rejected") do
          validate!("SELECT #{func}('x')", engine: "sqlite")
        end

      assert_equal :forbidden_function, err.reason
      assert_match(/#{Regexp.escape(func)}/i, err.message)
    end
  end

  def test_rejects_dangerous_psql_file_and_dblink_functions
    %w[
      pg_read_file pg_read_binary_file pg_ls_dir pg_stat_file
      lo_import lo_export
      set_config
      dblink dblink_connect dblink_connect_u
    ].each do |func|
      err =
        assert_raises(LogicaRb::SqlSafety::Violation, "expected #{func} to be rejected") do
          validate!("SELECT #{func}('x')", engine: "psql")
        end

      assert_equal :forbidden_function, err.reason
      assert_match(/#{Regexp.escape(func)}/i, err.message)
    end
  end

  def test_rejects_admin_and_sleep_functions_psql
    %w[
      pg_sleep pg_sleep_for pg_sleep_until
      pg_cancel_backend pg_terminate_backend pg_reload_conf
    ].each do |func|
      err =
        assert_raises(LogicaRb::SqlSafety::Violation, "expected #{func} to be rejected") do
          validate!("SELECT #{func}()", engine: "psql")
        end

      assert_equal :forbidden_function, err.reason
      assert_match(/#{Regexp.escape(func)}/i, err.message)
    end
  end

  def test_rejects_schema_qualified_calls_psql
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!("SELECT pg_catalog.pg_sleep_for('1 second')", engine: "psql")
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/pg_sleep_for/i, err.message)
  end

  def test_rejects_quoted_function_name_psql
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(%(SELECT "pg_reload_conf"()), engine: "psql")
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/pg_reload_conf/i, err.message)
  end

  def test_ignores_strings_and_comments
    validate!("SELECT 'pg_reload_conf()' AS msg", engine: "psql")
    validate!("SELECT 1 /* pg_cancel_backend(123) */", engine: "psql")
  end
end
