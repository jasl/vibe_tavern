# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "stringio"

class CLISmokeTest < Minitest::Test
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def with_stdin(text)
    original = $stdin
    $stdin = StringIO.new(text)
    yield
  ensure
    $stdin = original
  end

  def test_print_formats
    source = <<~LOGICA
      @Engine("sqlite");
      Test(x) :- x = 1;
    LOGICA

    Tempfile.create(["logica", ".l"]) do |file|
      file.write(source)
      file.flush

      compilation = LogicaRb::Transpiler.compile_file(file.path, predicates: "Test", engine: "sqlite")

      query_output = capture_stdout do
        status = LogicaRb::CLI.main([
          file.path,
          "print",
          "Test",
          "--engine=sqlite",
          "--format=query",
          "--no-color",
        ])
        assert_equal 0, status
      end

      script_output = capture_stdout do
        status = LogicaRb::CLI.main([
          file.path,
          "print",
          "Test",
          "--engine=sqlite",
          "--format=script",
          "--no-color",
        ])
        assert_equal 0, status
      end

      plan_output = capture_stdout do
        status = LogicaRb::CLI.main([
          file.path,
          "plan",
          "Test",
          "--engine=sqlite",
          "--no-color",
        ])
        assert_equal 0, status
      end

      assert_equal compilation.sql(:query), query_output
      assert_equal compilation.sql(:script), script_output
      assert_equal compilation.plan_json(pretty: true), plan_output

      validate_output = capture_stdout do
        validate_status = with_stdin(plan_output) do
          LogicaRb::CLI.main(["validate-plan", "-"])
        end
        assert_equal 0, validate_status
      end
      assert_equal "OK\n", validate_output
    end
  end
end
