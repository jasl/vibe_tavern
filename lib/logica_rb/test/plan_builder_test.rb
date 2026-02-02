# frozen_string_literal: true

require "test_helper"

class PlanBuilderTest < Minitest::Test
  def test_plan_shape
    source = <<~LOGICA
      @Engine("sqlite");
      Data(x) :- x = 1;
      Test(x) :- Data(x);
    LOGICA

    compilation = LogicaRb::Transpiler.compile_string(source, predicates: "Test", engine: "sqlite")
    plan = compilation.plan

    refute_nil plan

    plan_hash = plan.to_h
    assert_equal "logica_rb.plan.v1", plan_hash["schema"]
    assert_equal "sqlite", plan_hash["engine"]
    assert_equal ["Test"], plan_hash["final_predicates"]
    assert_equal [{ "predicate" => "Test", "node" => "Test", "kind" => "table" }], plan_hash["outputs"]
    assert plan_hash["config"].is_a?(Array)

    node_names = plan_hash["config"].map { |row| row["name"] }
    plan_hash.fetch("outputs").each do |out|
      assert_equal %w[kind node predicate], out.keys.sort
      assert_equal "table", out["kind"]
      assert_includes node_names, out["node"]
    end

    entry = plan_hash["config"].find { |row| row["name"] == "Test" }
    refute_nil entry
    assert_equal "final", entry["type"]
    assert_equal "query", entry.dig("action", "launcher")
  end
end
