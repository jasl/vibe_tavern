# frozen_string_literal: true

require "test_helper"
require "json"
require "yaml"

require_relative "../support/db_smoke/reference_plan_executor"
require_relative "../support/db_smoke/psql_adapter"

class PsqlDbSmokeTest < Minitest::Test
  MANIFEST_PATH = File.expand_path("../fixtures_manifest.yml", __dir__)
  FIXTURES_ROOT = File.expand_path("../fixtures", __dir__)

  def manifest
    @manifest ||= YAML.load_file(MANIFEST_PATH)
  end

  def compile_case(entry)
    src = File.join(FIXTURES_ROOT, entry.fetch("src"))
    predicate = entry["predicate"] || "Test"
    import_root = entry["import_root"] ? File.join(FIXTURES_ROOT, entry["import_root"]) : FIXTURES_ROOT
    library_profile = entry["library_profile"]
    capabilities = entry["capabilities"] || []

    LogicaRb::Transpiler.compile_file(
      src,
      predicates: predicate,
      engine: "psql",
      import_root: import_root,
      library_profile: library_profile,
      capabilities: capabilities
    )
  end

  def query_smoke_sql(sql)
    query = sql.to_s.strip.sub(/;\s*\z/, "")
    return nil unless query.start_with?("SELECT", "WITH")

    "SELECT 1 FROM (#{query}) AS logica_smoke LIMIT 1;"
  end

  def test_psql_db_smoke
    skip "Set LOGICA_DB_SMOKE=1 to enable DB smoke tests" unless ENV["LOGICA_DB_SMOKE"] == "1"

    database_url = ENV["DATABASE_URL"]
    if database_url.nil? || database_url.empty?
      skip "Set DATABASE_URL to run Postgres smoke tests"
    end

    probe = LogicaRb::DbSmoke::PsqlAdapter.build(database_url: database_url)
    skip "pg gem not installed (run bundle install)" unless probe
    probe.close

    manifest.fetch("tests").fetch("psql").each do |entry|
      name = entry.fetch("name")
      compilation = compile_case(entry)
      plan_hash = JSON.parse(compilation.plan_json(pretty: true))

      adapter = LogicaRb::DbSmoke::PsqlAdapter.build(database_url: database_url)
      begin
        executor = LogicaRb::DbSmoke::ReferencePlanExecutor.new(plan_hash)
        executor.execute!(adapter)

        plan_hash.fetch("outputs").each do |out|
          node_name = out.fetch("node")
          node = plan_hash.fetch("config").find { |n| n["name"] == node_name }
          raise "missing output node in config: #{node_name}" if node.nil?

          sql = node.dig("action", "sql")
          smoke_sql = query_smoke_sql(sql)
          adapter.exec_script(smoke_sql) if smoke_sql
        end
      rescue StandardError => e
        raise e.class, "psql smoke failed: #{name}: #{e.message}", e.backtrace
      ensure
        adapter&.close
      end
    end
  end
end
