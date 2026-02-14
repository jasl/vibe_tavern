# frozen_string_literal: true

require "test_helper"

class AgentCoreContribTokenCounterTest < ActiveSupport::TestCase
  class FakeTokenEstimator
    def estimate(text, model_hint: nil)
      _ = model_hint
      text.to_s.length
    end
  end

  test "Estimator counts text via token_estimator and applies per-message overhead" do
    counter =
      AgentCore::Contrib::TokenCounter::Estimator.new(
        token_estimator: FakeTokenEstimator.new,
        model_hint: "test",
        per_message_overhead: 5,
      )

    messages = [
      AgentCore::Message.new(role: :user, content: "hi"),
      AgentCore::Message.new(role: :assistant, content: "ok"),
    ]

    assert_equal 14, counter.count_messages(messages)
  end

  test "HeuristicWithOverhead applies per-message overhead" do
    counter = AgentCore::Contrib::TokenCounter::HeuristicWithOverhead.new(per_message_overhead: 3)
    messages = [
      AgentCore::Message.new(role: :user, content: ""),
      AgentCore::Message.new(role: :assistant, content: ""),
    ]

    assert_equal 6, counter.count_messages(messages)
  end
end
