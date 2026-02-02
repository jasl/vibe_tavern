# frozen_string_literal: true

require "test_helper"

class UntrustedGroundTest < Minitest::Test
  def parse_rules(source)
    LogicaRb::Parser.parse_file(source.to_s, import_root: "")["rule"]
  end

  def test_untrusted_source_rejects_ground_by_default
    source = <<~LOGICA
      @Engine("sqlite");
      @Ground(A);

      A(x:) :- x = 1;
    LOGICA

    err =
      assert_raises(LogicaRb::SourceSafety::Violation) do
        LogicaRb::SourceSafety::Validator.validate!(parse_rules(source), engine: "sqlite", trust: :untrusted, capabilities: [])
      end

    assert_match(/@Ground/, err.message)
    assert_match(/ground_declarations/, err.message)
  end

  def test_untrusted_source_allows_ground_with_capability
    source = <<~LOGICA
      @Engine("sqlite");
      @Ground(A);

      A(x:) :- x = 1;
    LOGICA

    LogicaRb::SourceSafety::Validator.validate!(
      parse_rules(source),
      engine: "sqlite",
      trust: :untrusted,
      capabilities: [:ground_declarations]
    )
  end
end
