# frozen_string_literal: true

require "test_helper"
require "yaml"

class ManifestTests < Minitest::Test
  MANIFEST_PATH = File.expand_path("fixtures_manifest.yml", __dir__)
  FIXTURES_ROOT = File.expand_path("fixtures", __dir__)
  SQL_GOLDENS_ROOT = File.expand_path("goldens/sql", __dir__)
  PLAN_GOLDENS_ROOT = File.expand_path("goldens/plan", __dir__)

  def manifest
    @manifest ||= YAML.load_file(MANIFEST_PATH)
  end

  def compile_case(entry, engine:)
    src = File.join(FIXTURES_ROOT, entry.fetch("src"))
    predicate = entry["predicate"] || "Test"
    import_root = entry["import_root"] ? File.join(FIXTURES_ROOT, entry["import_root"]) : FIXTURES_ROOT
    library_profile = entry["library_profile"]
    capabilities = entry["capabilities"] || []

    LogicaRb::Transpiler.compile_file(
      src,
      predicates: predicate,
      engine: engine,
      import_root: import_root,
      library_profile: library_profile,
      capabilities: capabilities
    )
  end

  def read_sql_golden(engine, name)
    File.binread(File.join(SQL_GOLDENS_ROOT, engine, "#{name}.sql"))
  end

  def read_plan_golden(engine, name)
    File.binread(File.join(PLAN_GOLDENS_ROOT, engine, "#{name}.json"))
  end

  def test_sqlite_manifest
    manifest.fetch("tests").fetch("sqlite").each do |entry|
      compilation = compile_case(entry, engine: "sqlite")
      name = entry.fetch("name")

      assert_equal read_sql_golden("sqlite", name), compilation.sql(:script), "sqlite sql mismatch: #{name}"
      assert_equal read_plan_golden("sqlite", name), compilation.plan_json(pretty: true), "sqlite plan mismatch: #{name}"
    end
  end

  def test_psql_manifest
    manifest.fetch("tests").fetch("psql").each do |entry|
      compilation = compile_case(entry, engine: "psql")
      name = entry.fetch("name")

      assert_equal read_sql_golden("psql", name), compilation.sql(:script), "psql sql mismatch: #{name}"
      assert_equal read_plan_golden("psql", name), compilation.plan_json(pretty: true), "psql plan mismatch: #{name}"
    end
  end

  def test_type_inference_manifest
    manifest.fetch("tests").fetch("type_inference_psql").each do |entry|
      src = File.join(FIXTURES_ROOT, entry.fetch("src"))
      output = LogicaRb::Pipeline.infer_types(File.read(src), dialect: "psql", import_root: FIXTURES_ROOT)
      expected = File.binread(File.join(FIXTURES_ROOT, entry.fetch("golden")))
      assert_equal expected, output, "typing mismatch: #{entry.fetch('name')}"
    end
  end

  def test_unsupported_smoke_manifest
    manifest.fetch("tests").fetch("unsupported_smoke").each do |entry|
      src = File.join(FIXTURES_ROOT, entry.fetch("src"))
      predicate = entry["predicate"] || "Test"
      assert_raises(LogicaRb::UnsupportedEngineError) do
        LogicaRb::Transpiler.compile_file(
          src,
          predicates: predicate,
          import_root: FIXTURES_ROOT
        )
      end
    end
  end
end
