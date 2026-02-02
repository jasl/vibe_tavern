# frozen_string_literal: true

require "test_helper"
require "json"
require "yaml"

require_relative "../support/db_smoke/reference_plan_executor"
require_relative "../support/db_smoke/sqlite_adapter"
require_relative "../support/result_table_parser"

class SqliteDbResultsTest < Minitest::Test
  MANIFEST_PATH = File.expand_path("../fixtures_manifest.yml", __dir__)
  FIXTURES_ROOT = File.expand_path("../fixtures", __dir__)

  def manifest
    @manifest ||= YAML.load_file(MANIFEST_PATH)
  end

  def db_results_entries
    manifest.fetch("tests").fetch("sqlite").select { |e| e["db_results"] || e["unsafe"] }
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

  def stable_sort_rows(rows)
    Array(rows).sort_by { |row| row_sort_key(row) }
  end

  def row_sort_key(row)
    Array(row).map { |v| v.nil? ? "" : v.to_s }.join("\u0001")
  end

  def quote_ident(name)
    %("#{name.to_s.gsub('"', '""')}")
  end

  def identifier_sql(name)
    str = name.to_s
    return str if /\A[a-zA-Z_][a-zA-Z0-9_]*\z/.match?(str)

    quote_ident(str)
  end

  def query_sql?(sql)
    sql.to_s.lstrip.start_with?("SELECT", "WITH", "VALUES")
  end

  def materialize_output_table!(adapter, node_name, node_sql)
    return unless query_sql?(node_sql)

    ident = identifier_sql(node_name)
    query = node_sql.to_s.strip.sub(/;\s*\z/, "")

    adapter.exec_script("CREATE TEMP TABLE #{ident} AS #{query};")
  end

  def test_sqlite_db_results
    skip "Set LOGICA_DB_RESULTS=1 to enable DB results tests" unless ENV["LOGICA_DB_RESULTS"] == "1"

    probe = LogicaRb::DbSmoke::SqliteAdapter.build
    skip "sqlite3 gem not installed (run bundle install)" unless probe
    probe.close

    entries = db_results_entries
    skip "No sqlite db_results cases marked in fixtures_manifest.yml" if entries.empty?

    unsafe_enabled = ENV["LOGICA_UNSAFE_IO"] == "1"
    runnable =
      entries.select do |entry|
        unsafe = Array(entry["unsafe"]).compact
        unsafe.empty? || unsafe_enabled
      end
    skip "No sqlite db_results cases enabled (set LOGICA_UNSAFE_IO=1 for unsafe entries)" if runnable.empty?

    runnable.each do |entry|
      name = entry.fetch("name")
      compilation = compile_case(entry)
      plan_hash = JSON.parse(compilation.plan_json(pretty: true))
      outputs = plan_hash.fetch("outputs")
      assert_equal 1, outputs.size, "db_results expects exactly 1 output for #{name}"

      golden_text = File.binread(File.join(FIXTURES_ROOT, entry.fetch("golden")))
      expected = ResultTableParser.parse(golden_text)

      adapter = LogicaRb::DbSmoke::SqliteAdapter.build
      begin
        LogicaRb::DbSmoke::ReferencePlanExecutor.execute!(adapter, plan_hash)

        outputs.each do |out|
          node_name = out.fetch("node")
          node = plan_hash.fetch("config").find { |n| n["name"] == node_name }
          raise "missing output node in config: #{node_name}" if node.nil?

          materialize_output_table!(adapter, node_name, node.dig("action", "sql"))
          actual = adapter.select_all("SELECT * FROM #{identifier_sql(node_name)};")

          assert_equal expected.fetch("columns"), actual.fetch("columns"), "sqlite columns mismatch: #{name}"
          assert_equal stable_sort_rows(expected.fetch("rows")), stable_sort_rows(actual.fetch("rows")), "sqlite rows mismatch: #{name}"
        end
      rescue StandardError => e
        raise e.class, "sqlite results failed: #{name}: #{e.message}", e.backtrace
      ensure
        adapter&.close
      end
    end
  end
end
