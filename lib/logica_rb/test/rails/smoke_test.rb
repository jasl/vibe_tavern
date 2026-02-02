# frozen_string_literal: true

require "test_helper"

class RailsIntegrationSmokeTest < Minitest::Test
  def test_rails_integration_installs_active_record_hook
    begin
      require "active_support/lazy_load_hooks"
    rescue LoadError
      skip "activesupport not installed"
    end

    require "logica_rb/rails"

    base = Class.new
    ActiveSupport.run_load_hooks(:active_record, base)

    assert_respond_to base, :logica_query
    assert_respond_to base, :logica
    assert_respond_to base, :logica_sql
    assert_respond_to base, :logica_result
    assert_respond_to base, :logica_relation
    assert_respond_to base, :logica_records
  end

  def test_engine_detector
    begin
      require "active_support/lazy_load_hooks"
    rescue LoadError
      skip "activesupport not installed"
    end

    require "logica_rb/rails"

    sqlite_conn = Struct.new(:adapter_name).new("SQLite")
    assert_equal "sqlite", LogicaRb::Rails::EngineDetector.detect(sqlite_conn)

    psql_conn = Struct.new(:adapter_name).new("PostgreSQL")
    assert_equal "psql", LogicaRb::Rails::EngineDetector.detect(psql_conn)
  end

  def test_executor_exec_script_uses_raw_drivers_when_present
    begin
      require "active_support/lazy_load_hooks"
    rescue LoadError
      skip "activesupport not installed"
    end

    require "logica_rb/rails"

    sqlite_raw =
      if defined?(::SQLite3::Database)
        Class.new(::SQLite3::Database) do
          attr_reader :batches

          def execute_batch(sql)
            @batches ||= []
            @batches << sql
          end
        end.new(":memory:")
      else
        sqlite3_mod = Object.const_defined?(:SQLite3) ? Object.const_get(:SQLite3) : Object.const_set(:SQLite3, Module.new)
        unless sqlite3_mod.const_defined?(:Database)
          sqlite3_mod.const_set(
            :Database,
            Class.new do
              attr_reader :batches

              def execute_batch(sql)
                @batches ||= []
                @batches << sql
              end
            end
          )
        end

        ::SQLite3::Database.new
      end

    pg_mod = Object.const_defined?(:PG) ? Object.const_get(:PG) : Object.const_set(:PG, Module.new)
    unless pg_mod.const_defined?(:Connection)
      pg_mod.const_set(
        :Connection,
        Class.new do
          attr_reader :execs

          def exec(sql)
            @execs ||= []
            @execs << sql
          end
        end
      )
    end

    sqlite_conn = Struct.new(:raw_connection) do
      def execute(_sql)
        raise "should not be called"
      end
    end.new(sqlite_raw)

    LogicaRb::Rails::Executor.new(connection: sqlite_conn).exec_script("SELECT 1;")
    assert_equal ["SELECT 1;"], sqlite_raw.batches

    pg_raw = ::PG::Connection.new
    pg_conn = Struct.new(:raw_connection) do
      def execute(_sql)
        raise "should not be called"
      end
    end.new(pg_raw)

    LogicaRb::Rails::Executor.new(connection: pg_conn).exec_script("SELECT 2;")
    assert_equal ["SELECT 2;"], pg_raw.execs
  end
end
