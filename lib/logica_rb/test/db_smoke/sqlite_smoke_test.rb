# frozen_string_literal: true

require "test_helper"
require "json"
require "yaml"

require_relative "../support/db_smoke/reference_plan_executor"
require_relative "../support/db_smoke/sqlite_adapter"

class SqliteDbSmokeTest < Minitest::Test
  MANIFEST_PATH = File.expand_path("../fixtures_manifest.yml", __dir__)
  FIXTURES_ROOT = File.expand_path("../fixtures", __dir__)

  UNSAFE_ENV_ALLOWLIST = {
    "file_io" => "LOGICA_UNSAFE_IO",
  }.freeze

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
      engine: "sqlite",
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

  def test_sqlite_db_smoke
    skip "Set LOGICA_DB_SMOKE=1 to enable DB smoke tests" unless ENV["LOGICA_DB_SMOKE"] == "1"

    probe = LogicaRb::DbSmoke::SqliteAdapter.build
    skip "sqlite3 gem not installed (run bundle install)" unless probe
    probe.close

    manifest.fetch("tests").fetch("sqlite").each do |entry|
      name = entry.fetch("name")
      unsafe = Array(entry["unsafe"]).compact.map(&:to_s)
      if unsafe.any? && !unsafe.all? { |cap| (env = UNSAFE_ENV_ALLOWLIST[cap]) && ENV[env] == "1" }
        next
      end

      compilation = compile_case(entry)
      plan_hash = JSON.parse(compilation.plan_json(pretty: true))

      adapter = LogicaRb::DbSmoke::SqliteAdapter.build
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
        raise e.class, "sqlite smoke failed: #{name}: #{e.message}", e.backtrace
      ensure
        adapter&.close
      end
    end
  end
end
