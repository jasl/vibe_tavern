# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class RailsImportWhitelistTest < Minitest::Test
  def test_source_allow_imports_requires_allowed_import_prefixes
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    Dir.mktmpdir do |dir|
      LogicaRb::Rails.configure do |c|
        c.import_root = dir
        c.allowed_import_prefixes = nil
      end

      query =
        LogicaRb::Rails.query(
          source: "import allowed.dep.Val; Test(v:) :- Val(v:);",
          predicate: "Test",
          allow_imports: true
        )

      err = assert_raises(ArgumentError) { query.sql }
      assert_match(/allowed_import_prefixes/i, err.message)
    ensure
      LogicaRb::Rails.configure do |c|
        c.import_root = nil
        c.allowed_import_prefixes = nil
      end
    end
  end

  def test_source_allow_imports_rejects_empty_allowed_import_prefixes
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    Dir.mktmpdir do |dir|
      LogicaRb::Rails.configure do |c|
        c.import_root = dir
        c.allowed_import_prefixes = []
      end

      query =
        LogicaRb::Rails.query(
          source: "import allowed.dep.Val; Test(v:) :- Val(v:);",
          predicate: "Test",
          allow_imports: true
        )

      err = assert_raises(ArgumentError) { query.sql }
      assert_match(/allowed_import_prefixes/i, err.message)
    ensure
      LogicaRb::Rails.configure do |c|
        c.import_root = nil
        c.allowed_import_prefixes = nil
      end
    end
  end

  def test_rejects_source_imports_outside_whitelist
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "evil"))
      File.write(
        File.join(dir, "evil", "dep.l"),
        <<~LOGICA
          Val(v:) :- v = 1;
        LOGICA
      )

      LogicaRb::Rails.configure do |c|
        c.import_root = dir
        c.allowed_import_prefixes = ["allowed"]
      end

      source = <<~LOGICA
        import evil.dep.Val;

        Test(v:) :- Val(v:);
      LOGICA

      query = LogicaRb::Rails.query(source: source, predicate: "Test", allow_imports: true)

      err = assert_raises(ArgumentError) { query.sql }
      assert_match(/not allowed/i, err.message)
    ensure
      LogicaRb::Rails.configure do |c|
        c.import_root = nil
        c.allowed_import_prefixes = nil
      end
    end
  end

  def test_rejects_invalid_import_paths_even_with_allowlist
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    Dir.mktmpdir do |dir|
      LogicaRb::Rails.configure do |c|
        c.import_root = dir
        c.allowed_import_prefixes = ["allowed"]
      end

      sources = [
        "import ../evil.Dep; Test(v:) :- v = 1;",
        "import /abs.evil.Dep; Test(v:) :- v = 1;",
        "import allowed..evil.Dep; Test(v:) :- v = 1;",
        "import allowed.evil..Dep; Test(v:) :- v = 1;",
        "import allowed.\u2603.Dep; Test(v:) :- v = 1;",
      ]

      sources.each do |source|
        query = LogicaRb::Rails.query(source: source, predicate: "Test", allow_imports: true)

        err = assert_raises(LogicaRb::Parser::ParsingException) { query.sql }
        assert_match(/Invalid import path segment/i, err.message)
      end
    ensure
      LogicaRb::Rails.configure do |c|
        c.import_root = nil
        c.allowed_import_prefixes = nil
      end
    end
  end

  def test_allows_source_imports_in_whitelist
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "allowed"))
      File.write(
        File.join(dir, "allowed", "dep.l"),
        <<~LOGICA
          Val(v:) :- v = 1;
        LOGICA
      )

      LogicaRb::Rails.configure do |c|
        c.import_root = dir
        c.allowed_import_prefixes = ["allowed"]
      end

      source = <<~LOGICA
        import allowed.dep.Val;

        Test(v:) :- Val(v:);
      LOGICA

      query = LogicaRb::Rails.query(source: source, predicate: "Test", allow_imports: true)
      assert_kind_of String, query.sql
    ensure
      LogicaRb::Rails.configure do |c|
        c.import_root = nil
        c.allowed_import_prefixes = nil
      end
    end
  end
end
