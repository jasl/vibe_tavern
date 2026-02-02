# frozen_string_literal: true

require "test_helper"

class RailsQuerySourceTest < Minitest::Test
  def test_source_query_result_and_relation
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        age INTEGER NOT NULL,
        name TEXT NOT NULL
      );
    SQL
    ActiveRecord::Base.connection.execute("INSERT INTO users (id, age, name) VALUES (1, 10, 'Kid')")
    ActiveRecord::Base.connection.execute("INSERT INTO users (id, age, name) VALUES (2, 20, 'Alice')")
    ActiveRecord::Base.connection.execute("INSERT INTO users (id, age, name) VALUES (3, 30, 'Bob')")

    user_model = Class.new(ActiveRecord::Base) do
      self.table_name = "users"
    end
    user_model.reset_column_information

    source = <<~LOGICA
      @Engine("sqlite");

      AdultUsers(id:, age:, name:) :-
        `((select id, age, name from users))`(id:, age:, name:),
        age >= 18;
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "AdultUsers", trusted: false, allowed_relations: ["users"])

    result = query.result
    assert_kind_of ActiveRecord::Result, result
    assert_equal %w[id age name], result.columns
    assert_equal [[2, 20, "Alice"], [3, 30, "Bob"]], result.rows

    rel = query.relation(model: user_model).order("logica_adultusers.age ASC")
    assert_equal [20, 30], rel.map(&:age)
    assert_equal %w[Alice Bob], rel.map(&:name)
  end

  def test_source_query_is_validated_as_query_only
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
    err = assert_raises(LogicaRb::SqlSafety::Violation) { query.result }
    assert_match(/Multiple SQL statements/i, err.message)
  end

  def test_source_defaults_are_safe
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      Test(x:) :- x = 1;
    LOGICA

    assert_raises(ArgumentError) { LogicaRb::Rails.query(source: source, predicate: "Test", format: :script, trusted: false) }
    assert_raises(ArgumentError) { LogicaRb::Rails.query(source: source, predicate: "Test", format: :plan, trusted: false) }
  end

  def test_source_imports_are_disabled_by_default
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      import dep.DepValue;

      Test(v:) :- DepValue(v:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Test", trusted: false)

    err = assert_raises(ArgumentError) { query.sql }
    assert_match(/Imports are disabled/i, err.message)
  end
end
