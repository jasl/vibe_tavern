# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Tools::Policy::DecisionTest < Minitest::Test
  def test_allow
    d = AgentCore::Resources::Tools::Policy::Decision.allow
    assert d.allowed?
    refute d.denied?
    refute d.requires_confirmation?
  end

  def test_deny
    d = AgentCore::Resources::Tools::Policy::Decision.deny(reason: "not allowed")
    refute d.allowed?
    assert d.denied?
    assert_equal "not allowed", d.reason
  end

  def test_confirm
    d = AgentCore::Resources::Tools::Policy::Decision.confirm(reason: "needs approval")
    refute d.allowed?
    refute d.denied?
    assert d.requires_confirmation?
  end

  def test_invalid_outcome
    assert_raises(ArgumentError) do
      AgentCore::Resources::Tools::Policy::Decision.new(outcome: :invalid)
    end
  end
end

class AgentCore::Resources::Tools::Policy::BaseTest < Minitest::Test
  def test_default_filter_passes_through
    policy = AgentCore::Resources::Tools::Policy::Base.new
    tools = [{ name: "read" }, { name: "write" }]
    ctx = AgentCore::ExecutionContext.from(nil)
    assert_equal tools, policy.filter(tools: tools, context: ctx)
  end

  def test_default_authorize_allows
    policy = AgentCore::Resources::Tools::Policy::Base.new
    ctx = AgentCore::ExecutionContext.from(nil)
    decision = policy.authorize(name: "read", context: ctx)
    assert decision.allowed?
  end
end
