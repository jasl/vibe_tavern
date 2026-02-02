# frozen_string_literal: true

require "test_helper"

class SqliteAuthorizerHardeningTest < Minitest::Test
  def test_with_authorizer_hardens_and_restores_pragmas
    begin
      require "sqlite3"
    rescue LoadError
      skip "sqlite3 gem not installed"
    end

    db = SQLite3::Database.new(":memory:")
    db.execute("CREATE TABLE allowed_table(id INTEGER PRIMARY KEY)")
    db.execute("INSERT INTO allowed_table (id) VALUES (1)")

    begin
      db.execute("PRAGMA query_only = 0")
      db.execute("PRAGMA trusted_schema = 1")
      assert_equal 0, Integer(db.get_first_value("PRAGMA query_only"))
      assert_equal 1, Integer(db.get_first_value("PRAGMA trusted_schema"))
    rescue StandardError => e
      skip "SQLite does not support query_only/trusted_schema pragmas in this build: #{e.class}: #{e.message}"
    end

    policy = LogicaRb::AccessPolicy.untrusted(engine: "sqlite", allowed_relations: ["allowed_table"])

    LogicaRb::SqliteSafety::Authorizer.with_authorizer(db, capabilities: policy.effective_capabilities, access_policy: policy, harden: true) do
      assert_equal 1, Integer(db.get_first_value("PRAGMA query_only"))
      assert_equal 0, Integer(db.get_first_value("PRAGMA trusted_schema"))

      assert_raises(SQLite3::AuthorizationException, SQLite3::ReadOnlyException) do
        db.execute("INSERT INTO allowed_table (id) VALUES (2)")
      end
    end

    assert_equal 0, Integer(db.get_first_value("PRAGMA query_only"))
    assert_equal 1, Integer(db.get_first_value("PRAGMA trusted_schema"))

    db.execute("INSERT INTO allowed_table (id) VALUES (2)")
    assert_equal [[1], [2]], db.execute("SELECT id FROM allowed_table ORDER BY id")
  ensure
    db&.close
  end
end
