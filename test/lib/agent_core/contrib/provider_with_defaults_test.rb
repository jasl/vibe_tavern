# frozen_string_literal: true

require "test_helper"

class AgentCoreContribProviderWithDefaultsTest < ActiveSupport::TestCase
  class FakeProvider < AgentCore::Resources::Provider::Base
    attr_reader :requests

    def initialize
      @requests = []
    end

    def name = "fake"

    def chat(messages:, model:, tools: nil, stream: false, **options)
      @requests << { messages: messages, model: model, tools: tools, stream: stream, options: options }

      AgentCore::Resources::Provider::Response.new(
        message: AgentCore::Message.new(role: :assistant, content: "ok"),
        usage: nil,
        raw: nil,
        stop_reason: :end_turn,
      )
    end
  end

  test "merges request_defaults with per-call options (per-call wins)" do
    provider = FakeProvider.new
    wrapped =
      AgentCore::Contrib::ProviderWithDefaults.new(
        provider: provider,
        request_defaults: { temperature: 0.2, max_tokens: 10 },
      )

    wrapped.chat(
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      model: "m1",
      temperature: 0.7,
    )

    req = provider.requests.first
    assert_equal "m1", req.fetch(:model)
    assert_equal 0.7, req.fetch(:options).fetch(:temperature)
    assert_equal 10, req.fetch(:options).fetch(:max_tokens)
  end

  test "rejects reserved keys in request_defaults" do
    provider = FakeProvider.new

    assert_raises(ArgumentError) do
      AgentCore::Contrib::ProviderWithDefaults.new(
        provider: provider,
        request_defaults: { model: "nope" },
      )
    end
  end

  test "canonicalizes stop_sequences to stop (and per-call wins)" do
    provider = FakeProvider.new
    wrapped =
      AgentCore::Contrib::ProviderWithDefaults.new(
        provider: provider,
        request_defaults: { stop: ["x"] },
      )

    wrapped.chat(
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      model: "m1",
      stop_sequences: ["y"],
    )

    req = provider.requests.first
    assert_equal ["y"], req.fetch(:options).fetch(:stop)
    refute req.fetch(:options).key?(:stop_sequences)
  end
end
