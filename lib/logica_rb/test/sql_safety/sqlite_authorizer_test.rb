# frozen_string_literal: true

require "test_helper"

class SqliteAuthorizerTest < Minitest::Test
  def test_authorizer_enforces_table_allowlist_and_blocks_sqlite_master
    begin
      require "sqlite3"
    rescue LoadError
      skip "sqlite3 gem not installed"
    end

    db = SQLite3::Database.new(":memory:")
    db.execute("CREATE TABLE allowed_table(id INTEGER PRIMARY KEY)")
    db.execute("INSERT INTO allowed_table (id) VALUES (1)")

    policy = LogicaRb::AccessPolicy.untrusted(engine: "sqlite", allowed_relations: ["allowed_table"])

    LogicaRb::SqliteSafety::Authorizer.with_untrusted_policy(db, policy) do
      rows = db.execute("SELECT id FROM allowed_table")
      assert_equal [[1]], rows

      assert_raises(SQLite3::AuthorizationException) do
        db.execute("SELECT name FROM sqlite_master")
      end

      assert_raises(SQLite3::AuthorizationException) do
        db.execute("PRAGMA table_info(allowed_table)")
      end
    end
  ensure
    db&.close
  end

  def test_authorizer_blocks_load_extension
    begin
      require "sqlite3"
    rescue LoadError
      skip "sqlite3 gem not installed"
    end

    db = SQLite3::Database.new(":memory:")
    policy = LogicaRb::AccessPolicy.untrusted(engine: "sqlite", allowed_relations: [])

    LogicaRb::SqliteSafety::Authorizer.with_untrusted_policy(db, policy) do
      assert_raises(SQLite3::Exception) do
        db.execute("SELECT load_extension('x')")
      end
    end
  ensure
    db&.close
  end
end
