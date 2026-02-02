# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"

class CLIValidatePlanTest < Minitest::Test
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  def with_stdin(text)
    original = $stdin
    $stdin = StringIO.new(text)
    yield
  ensure
    $stdin = original
  end

  def test_validate_plan_ok
    source = <<~LOGICA
      @Engine("sqlite");
      Test(x) :- x = 1;
    LOGICA

    compilation = LogicaRb::Transpiler.compile_string(source, predicates: "Test", engine: "sqlite")
    plan_json = compilation.plan_json(pretty: true)

    stdout = capture_stdout do
      stderr = capture_stderr do
        status = with_stdin(plan_json) do
          LogicaRb::CLI.main(["validate-plan", "-"])
        end
        assert_equal 0, status
      end
      assert_equal "", stderr
    end
    assert_equal "OK\n", stdout
  end

  def test_validate_plan_fails_with_clear_error
    source = <<~LOGICA
      @Engine("sqlite");
      Test(x) :- x = 1;
    LOGICA

    compilation = LogicaRb::Transpiler.compile_string(source, predicates: "Test", engine: "sqlite")
    plan_hash = JSON.parse(compilation.plan_json(pretty: true))
    plan_hash.fetch("outputs").fetch(0)["node"] = "MissingNode"

    stderr = capture_stderr do
      stdout = capture_stdout do
        status = with_stdin(JSON.generate(plan_hash)) do
          LogicaRb::CLI.main(["validate-plan", "-"])
        end
        assert_equal 1, status
      end
      assert_equal "", stdout
    end

    assert_includes stderr, "outputs references missing node: MissingNode"
  end

  def test_validate_plan_rejects_invalid_json
    stderr = capture_stderr do
      stdout = capture_stdout do
        status = with_stdin("{") do
          LogicaRb::CLI.main(["validate-plan", "-"])
        end
        assert_equal 1, status
      end
      assert_equal "", stdout
    end

    assert_includes stderr, "Invalid JSON:"
  end
end
