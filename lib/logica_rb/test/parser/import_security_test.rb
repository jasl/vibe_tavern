# frozen_string_literal: true

require "test_helper"

class ImportSecurityTest < Minitest::Test
  def test_rejects_import_path_segments_with_path_traversal_or_slashes
    source = <<~LOGICA
      import a../b.Pred;

      Test(x:) :- x = 1;
    LOGICA

    err = assert_raises(LogicaRb::Parser::ParsingException) do
      LogicaRb::Parser.parse_file(source, import_root: ".", parsed_imports: {})
    end

    assert_match(/Invalid import path segment/i, err.message)
  end
end
