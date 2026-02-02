# frozen_string_literal: true

require "test_helper"

require "tmpdir"

class RailsCacheReloadTest < Minitest::Test
  def test_cache_key_changes_with_mtime_and_imports
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    LogicaRb::Rails.configure do |c|
      c.cache = true
      c.cache_mode = :mtime
    end

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    Dir.mktmpdir("logica_rb") do |dir|
      File.write(
        File.join(dir, "dep.l"),
        <<~LOGICA
          DepValue(v:) :- v = 1;
        LOGICA
      )

      File.write(
        File.join(dir, "main.l"),
        <<~LOGICA
          import dep.DepValue;

          Test(v:) :- DepValue(v:);
        LOGICA
      )

      definition = LogicaRb::Rails::QueryDefinition.new(
        name: :test,
        file: "main.l",
        predicate: "Test",
        engine: :auto,
        import_root: dir
      )

      query = LogicaRb::Rails::Query.new(definition, connection: ActiveRecord::Base.connection, cache: LogicaRb::Rails.cache)

      compilation1 = query.compile
      sql1 = query.sql
      compilation2 = query.compile
      assert_same compilation1, compilation2

      sleep 1.1
      File.write(
        File.join(dir, "dep.l"),
        <<~LOGICA
          DepValue(v:) :- v = 2;
        LOGICA
      )

      compilation3 = query.compile
      sql2 = query.sql
      refute_same compilation1, compilation3
      refute_equal sql1, sql2

      sleep 1.1
      File.write(
        File.join(dir, "main.l"),
        <<~LOGICA
          import dep.DepValue;

          Test(v:) :-
            DepValue(v: v0),
            v = v0 + 10;
        LOGICA
      )

      compilation4 = query.compile
      sql3 = query.sql
      refute_same compilation3, compilation4
      refute_equal sql2, sql3

      LogicaRb::Rails.clear_cache!
      compilation5 = query.compile
      refute_same compilation4, compilation5
    end
  end
end
