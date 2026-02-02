# frozen_string_literal: true

require "test_helper"

require "tmpdir"

class RailsQueryRelationTest < Minitest::Test
  def test_relation_is_chainable_for_parameterization
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

    user_model = Class.new(ActiveRecord::Base) do
      self.table_name = "users"
    end
    user_model.reset_column_information

    Dir.mktmpdir("logica_rb") do |dir|
      File.write(
        File.join(dir, "users.l"),
        <<~LOGICA
          @Engine("sqlite");

          UserData(id: 1, age: 10, name: "Kid");
          UserData(id: 2, age: 20, name: "Alice");
          UserData(id: 3, age: 30, name: "Bob");

          AdultUsers(id:, age:, name:) :- UserData(id:, age:, name:);
        LOGICA
      )

      user_model.logica_query(:adult_users, file: "users.l", predicate: "AdultUsers", import_root: dir)

      rel = user_model.logica_relation(:adult_users)
      rel = rel.where("logica_adultusers.age >= ?", 18).order("logica_adultusers.age ASC")

      assert_equal [20, 30], rel.map(&:age)
      assert_equal %w[Alice Bob], rel.map(&:name)
    end
  end
end
