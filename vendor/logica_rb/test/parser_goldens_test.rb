# frozen_string_literal: true

require "test_helper"

class ParserGoldensTest < Minitest::Test
  GOLDENS_DIR = File.expand_path("fixtures/parser_goldens", __dir__)
  FIXTURES_ROOT = File.expand_path("fixtures", __dir__)

  def test_parser_goldens
    golden_files = Dir.glob(File.join(GOLDENS_DIR, "*.l.ast.json")).sort
    skip "No parser goldens found in fixtures/parser_goldens" if golden_files.empty?

    golden_files.each do |golden_path|
      base = File.basename(golden_path, ".ast.json")
      source_path = File.join(FIXTURES_ROOT, "integration_tests", base)
      assert File.file?(source_path), "Missing parser fixture for #{base}"

      source = File.binread(source_path)
      file_name = source.include?("Signa inter verba conjugo, symbolum infixus evoco!") ? "main" : base
      parsed = LogicaRb::Parser.parse_file(source, this_file_name: file_name, import_root: FIXTURES_ROOT)
      output = LogicaRb::Pipeline.pretty_json(parsed.fetch("rule"))
      expected = File.binread(golden_path)
      assert_equal expected, output, "parser golden mismatch: #{base}"
    end
  end
end
