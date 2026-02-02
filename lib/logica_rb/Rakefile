# frozen_string_literal: true

require "bundler/setup"

APP_RAKEFILE = File.expand_path("dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create do |t|
  t.framework = %(require "test_helper")
  t.test_globs = [
    "test/*_test.rb",
    "test/support/**/*_test.rb",
    "test/source_safety/**/*_test.rb",
    "test/sql_safety/**/*_test.rb",
    "test/db_smoke/**/*_test.rb",
    "test/parser/**/*_test.rb",
  ]
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[test rubocop]

namespace :test do
  desc "Run Rails integration tests (SQLite)"
  task :rails_sqlite do
    files = %w[
      test/rails/smoke_test.rb
      test/rails/query_relation_test.rb
      test/rails/query_result_test.rb
      test/rails/query_source_test.rb
      test/rails/query_source_safety_test.rb
      test/rails/import_whitelist_test.rb
      test/rails/cache_reload_test.rb
    ]

    sh "bundle exec ruby -Itest -e 'ARGV.each { |f| load f }' -- #{files.join(" ")}"
  end

  desc "Run Rails integration tests (Postgres, requires DATABASE_URL)"
  task :rails_psql do
    sh "bundle exec ruby -Itest test/rails/query_psql_smoke_test.rb"
  end

  desc "Run SQLite DB smoke tests"
  task :db_smoke_sqlite do
    sh({ "LOGICA_DB_SMOKE" => "1" }, "bundle exec ruby -Itest test/db_smoke/sqlite_smoke_test.rb")
  end

  desc "Run Postgres DB smoke tests (requires DATABASE_URL)"
  task :db_smoke_psql do
    sh({ "LOGICA_DB_SMOKE" => "1" }, "bundle exec ruby -Itest test/db_smoke/psql_smoke_test.rb")
  end

  desc "Run all DB smoke tests"
  task db_smoke: %i[db_smoke_sqlite db_smoke_psql]

  desc "Run SQLite DB results tests"
  task :db_results_sqlite do
    sh({ "LOGICA_DB_RESULTS" => "1" }, "bundle exec ruby -Itest test/db_results/sqlite_results_test.rb")
  end

  desc "Run Postgres DB results tests (requires DATABASE_URL)"
  task :db_results_psql do
    sh({ "LOGICA_DB_RESULTS" => "1" }, "bundle exec ruby -Itest test/db_results/psql_results_test.rb")
  end

  desc "Run all DB results tests"
  task db_results: %i[db_results_sqlite db_results_psql]
end

namespace :goldens do
  desc "Generate SQL and plan goldens"
  task :generate do
    require "yaml"
    require "fileutils"

    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "logica_rb"

    manifest_path = File.expand_path("test/fixtures_manifest.yml", __dir__)
    fixtures_root = File.expand_path("test/fixtures", __dir__)
    sql_root = File.expand_path("test/goldens/sql", __dir__)
    plan_root = File.expand_path("test/goldens/plan", __dir__)

    manifest = YAML.load_file(manifest_path)

    generate = lambda do |entry, engine|
      src = File.join(fixtures_root, entry.fetch("src"))
      predicate = entry["predicate"] || "Test"
      import_root = entry["import_root"] ? File.join(fixtures_root, entry["import_root"]) : fixtures_root
      library_profile = entry["library_profile"]
      capabilities = entry["capabilities"] || []

      compilation = LogicaRb::Transpiler.compile_file(
        src,
        predicates: predicate,
        engine: engine,
        import_root: import_root,
        library_profile: library_profile,
        capabilities: capabilities
      )

      name = entry.fetch("name")
      sql_path = File.join(sql_root, engine, "#{name}.sql")
      plan_path = File.join(plan_root, engine, "#{name}.json")

      FileUtils.mkdir_p(File.dirname(sql_path))
      FileUtils.mkdir_p(File.dirname(plan_path))

      File.write(sql_path, compilation.sql(:script))
      LogicaRb::PlanValidator.validate!(compilation.plan.to_h)
      File.write(plan_path, compilation.plan_json(pretty: true))
    end

    manifest.fetch("tests").fetch("sqlite").each do |entry|
      generate.call(entry, "sqlite")
    end

    manifest.fetch("tests").fetch("psql").each do |entry|
      generate.call(entry, "psql")
    end
  end
end

namespace :release do
  desc "Build and install the gem in a temp dir, then run basic checks"
  task :sanity do
    require "fileutils"

    require_relative "lib/logica_rb/version"

    version = LogicaRb::VERSION
    gemspec = File.expand_path("logica_rb.gemspec", __dir__)

    Dir.chdir(__dir__) do
      sh "gem build #{gemspec}"

      gem_file = File.expand_path("logica_rb-#{version}.gem", __dir__)
      install_dir = File.expand_path("tmp/gem_install", __dir__)
      FileUtils.rm_rf(install_dir)

      sh "gem install #{gem_file} --install-dir #{install_dir} --no-document"

      clean_env = {
        "GEM_HOME" => install_dir,
        "GEM_PATH" => install_dir,
        "PATH" => "#{install_dir}/bin:#{ENV.fetch("PATH", "")}",
        "BUNDLE_GEMFILE" => "",
        "BUNDLE_BIN_PATH" => "",
        "BUNDLER_VERSION" => "",
        "RUBYLIB" => "",
        "RUBYOPT" => "",
      }

      require "bundler"

      Bundler.with_unbundled_env do
        sh clean_env, %(ruby -e 'require "logica_rb"; puts LogicaRb::VERSION')
        sh clean_env, "logica --help"

        begin
          sh clean_env, %(ruby -e 'require "rails"; require "generators/logica_rb/install/install_generator"')
        rescue StandardError
          warn "Skipping generator require check (rails not available)."
        end
      end
    end
  end
end
