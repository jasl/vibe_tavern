# frozen_string_literal: true

require "test_helper"

require "tmpdir"

class RailsQueryPsqlSmokeTest < Minitest::Test
  def test_executes_against_postgres
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    database_url = ENV["DATABASE_URL"]
    if database_url.nil? || database_url.empty?
      skip "Set DATABASE_URL to run Postgres Rails integration tests"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(database_url)

    Dir.mktmpdir("logica_rb") do |dir|
      file_path = File.join(dir, "users.l")
      File.write(
        file_path,
        <<~LOGICA
          @Engine("psql");

          UserData(id: 1, age: 20, name: "Alice");
          UserData(id: 2, age: 30, name: "Bob");

          Users(id:, age:, name:) :- UserData(id:, age:, name:);
        LOGICA
      )

      definition = LogicaRb::Rails::QueryDefinition.new(
        name: :users,
        file: file_path,
        predicate: "Users",
        engine: :auto
      )

      query = LogicaRb::Rails::Query.new(definition, connection: ActiveRecord::Base.connection, cache: LogicaRb::Rails.cache)
      result = query.result

      assert_kind_of ActiveRecord::Result, result
      assert_equal %w[id age name], result.columns
      assert_equal [[1, 20, "Alice"], [2, 30, "Bob"]], result.rows
    end
  end
end
