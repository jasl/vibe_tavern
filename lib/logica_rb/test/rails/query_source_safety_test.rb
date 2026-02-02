# frozen_string_literal: true

require "test_helper"

class RailsQuerySourceSafetyTest < Minitest::Test
  def test_untrusted_source_query_rejects_non_allowlisted_function
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(x:) :-
        `((select my_evil(1) as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    err = assert_raises(LogicaRb::SqlSafety::Violation) { query.sql }
    assert_equal :function_not_allowed, err.reason
    assert_equal "my_evil", err.details&.dig(:function)
  end

  def test_untrusted_source_query_allows_rails_minimal_aggregations_by_default
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE TABLE events (
        kind TEXT NOT NULL,
        amount INTEGER NOT NULL
      );
    SQL
    ActiveRecord::Base.connection.execute("INSERT INTO events (kind, amount) VALUES ('a', 10)")
    ActiveRecord::Base.connection.execute("INSERT INTO events (kind, amount) VALUES ('a', 5)")
    ActiveRecord::Base.connection.execute("INSERT INTO events (kind, amount) VALUES ('b', 7)")

    source = <<~LOGICA
      @Engine("sqlite");

      Totals(kind:, total:, n:) :-
        `((select kind, SUM(amount) as total, COUNT(*) as n from events group by kind))`(kind:, total:, n:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Totals", trusted: false, allowed_relations: ["events"])
    result = query.result

    assert_equal %w[kind total n], result.columns
    assert_equal [["a", 15, 2], ["b", 7, 1]], result.rows
  end

  def test_untrusted_source_query_rejects_lower_by_default
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(x:) :-
        `((select lower('x') as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    err = assert_raises(LogicaRb::SqlSafety::Violation) { query.sql }
    assert_equal :function_not_allowed, err.reason
    assert_equal "lower", err.details&.dig(:function)
  end

  def test_untrusted_source_query_ignores_dangerous_function_names_in_strings
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Safe(x:) :-
        `((select 'pg_read_file(' as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Safe", trusted: false)

    result = query.result
    assert_equal %w[x], result.columns
    assert_equal [["pg_read_file("]], result.rows
  end

  def test_untrusted_source_query_raises_violation_for_dangerous_sql
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(x:) :-
        `((select 1 as x; select 2 as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SqlSafety::Violation) { query.result }
  end

  def test_untrusted_source_query_rejects_sqlexpr
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() = SqlExpr("1", {x: 1});
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }
  end

  def test_untrusted_source_query_rejects_file_io_builtins
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() = ReadFile("/tmp/x");
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() :- WriteFile("/tmp/x", content: "[1,2,3]") == "OK";
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }
  end

  def test_untrusted_source_query_rejects_sqlite_master_reference
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(n:) :-
        `((select name as n from "sqlite_master"))`(n:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false, allowed_relations: ["users"])

    err = assert_raises(LogicaRb::SqlSafety::Violation) { query.sql }
    assert_equal :denied_schema, err.reason
    assert_match(/sqlite_master/i, err.message)
  end
end
