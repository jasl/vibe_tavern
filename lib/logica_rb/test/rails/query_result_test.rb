# frozen_string_literal: true

require "test_helper"

require "tmpdir"

class RailsQueryResultTest < Minitest::Test
  def test_result_returns_active_record_result
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    Dir.mktmpdir("logica_rb") do |dir|
      file_path = File.join(dir, "one.l")
      File.write(
        file_path,
        <<~LOGICA
          @Engine("sqlite");
          One(x:) :- x = 1;
        LOGICA
      )

      definition = LogicaRb::Rails::QueryDefinition.new(
        name: :one,
        file: file_path,
        predicate: "One",
        engine: :auto
      )

      query = LogicaRb::Rails::Query.new(definition, connection: ActiveRecord::Base.connection, cache: LogicaRb::Rails.cache)
      result = query.result

      assert_kind_of ActiveRecord::Result, result
      assert_equal ["x"], result.columns
      assert_equal [[1]], result.rows
    end
  end
end
