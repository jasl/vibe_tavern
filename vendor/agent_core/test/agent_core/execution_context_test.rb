# frozen_string_literal: true

require "test_helper"

class AgentCore::ExecutionContextTest < Minitest::Test
  def test_from_nil_builds_defaults
    ctx = AgentCore::ExecutionContext.from(nil)

    assert_instance_of AgentCore::ExecutionContext, ctx
    refute ctx.run_id.to_s.strip.empty?
    assert_equal({}, ctx.attributes)
    assert_instance_of AgentCore::Observability::NullInstrumenter, ctx.instrumenter
    assert_respond_to ctx.clock, :monotonic
    assert_respond_to ctx.clock, :now
  end

  def test_from_hash_requires_symbol_keys
    assert_raises(ArgumentError) do
      AgentCore::ExecutionContext.from({ "user_id" => 123 })
    end

    ctx = AgentCore::ExecutionContext.from({ user_id: 123 })
    assert_equal({ user_id: 123 }, ctx.attributes)
  end

  def test_from_accepts_keyword_attributes
    ctx = AgentCore::ExecutionContext.from(user_id: 123, cwd: "/tmp")

    assert_equal 123, ctx.attributes[:user_id]
    assert_equal "/tmp", ctx.attributes[:cwd]
  end

  def test_from_execution_context_can_override_instrumenter
    base = AgentCore::ExecutionContext.from({ user_id: 1 })
    recorder = AgentCore::Observability::TraceRecorder.new(capture: :none)

    ctx = AgentCore::ExecutionContext.from(base, instrumenter: recorder)

    assert_equal base.run_id, ctx.run_id
    assert_equal({ user_id: 1 }, ctx.attributes)
    assert_same recorder, ctx.instrumenter
  end
end
