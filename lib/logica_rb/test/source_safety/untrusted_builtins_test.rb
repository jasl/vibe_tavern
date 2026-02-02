# frozen_string_literal: true

require "test_helper"

class UntrustedBuiltinsTest < Minitest::Test
  def parse_rules(source)
    LogicaRb::Parser.parse_file(source.to_s, import_root: "")["rule"]
  end

  def test_untrusted_source_rejects_file_io_console_and_external_exec_calls
    cases = [
      ["ReadFile", :file_io, <<~LOGICA],
        @Engine("sqlite");
        Evil() = ReadFile("/tmp/x");
      LOGICA
      ["ReadJson", :file_io, <<~LOGICA],
        @Engine("sqlite");
        Evil() = ReadJson("/tmp/x");
      LOGICA
      ["WriteFile", :file_io, <<~LOGICA],
        @Engine("sqlite");
        Evil() :- WriteFile("/tmp/x", content: "ok") == "OK";
      LOGICA
      ["PrintToConsole", :console, <<~LOGICA],
        @Engine("sqlite");
        Evil() :- PrintToConsole("hi");
      LOGICA
      ["RunClingo", :external_exec, <<~LOGICA],
        @Engine("sqlite");
        Evil() = RunClingo("x");
      LOGICA
      ["RunClingoFile", :external_exec, <<~LOGICA],
        @Engine("sqlite");
        Evil() = RunClingoFile("/tmp/x");
      LOGICA
      ["Intelligence", :external_exec, <<~LOGICA],
        @Engine("sqlite");
        Evil() = Intelligence("x");
      LOGICA
    ]

    cases.each do |predicate_name, capability, source|
      err =
        assert_raises(LogicaRb::SourceSafety::Violation, "expected #{predicate_name} to be rejected") do
          LogicaRb::SourceSafety::Validator.validate!(
            parse_rules(source),
            engine: "sqlite",
            trust: :untrusted,
            capabilities: []
          )
        end

      assert_match(/#{Regexp.escape(predicate_name)}/, err.message)
      assert_match(/#{Regexp.escape(capability.to_s)}/, err.message)
    end
  end

  def test_untrusted_source_allows_capability_opt_in
    cases = [
      [:file_io, <<~LOGICA],
        @Engine("sqlite");
        Ok() = ReadFile("/tmp/x");
      LOGICA
      [:console, <<~LOGICA],
        @Engine("sqlite");
        Ok() :- PrintToConsole("hi");
      LOGICA
      [:external_exec, <<~LOGICA],
        @Engine("sqlite");
        Ok() = RunClingo("x");
      LOGICA
    ]

    cases.each do |capability, source|
      LogicaRb::SourceSafety::Validator.validate!(
        parse_rules(source),
        engine: "sqlite",
        trust: :untrusted,
        capabilities: [capability]
      )
    end
  end
end
