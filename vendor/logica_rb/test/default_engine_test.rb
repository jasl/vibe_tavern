# frozen_string_literal: true

require "test_helper"

class DefaultEngineTest < Minitest::Test
  def test_default_engine_is_sqlite
    source = <<~LOGICA
      Test(x) :- x = 1;
    LOGICA

    compilation = LogicaRb::Transpiler.compile_string(source, predicates: "Test")

    assert_equal "sqlite", compilation.engine
    assert_equal "sqlite", compilation.plan.to_h.fetch("engine")
  end
end
