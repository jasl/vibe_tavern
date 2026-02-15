# frozen_string_literal: true

require "test_helper"

class AgentCoreContribLanguagePolicyFinalRewriterTest < ActiveSupport::TestCase
  class FakeProvider < AgentCore::Resources::Provider::Base
    attr_reader :requests

    def initialize(reply_text:)
      @reply_text = reply_text
      @requests = []
    end

    def name = "fake"

    def chat(messages:, model:, tools: nil, stream: false, **options)
      raise ArgumentError, "expected stream=false" if stream

      @requests << { messages: messages, model: model, tools: tools, options: options }

      AgentCore::Resources::Provider::Response.new(
        message: AgentCore::Message.new(role: :assistant, content: @reply_text),
        usage: nil,
        raw: nil,
        stop_reason: :end_turn,
      )
    end
  end

  test "rewrite sends a no-tools request and returns rewritten text" do
    provider = FakeProvider.new(reply_text: "你好")

    out =
      AgentCore::Contrib::LanguagePolicy::FinalRewriter.rewrite(
        provider: provider,
        model: "m1",
        text: "hello",
        target_lang: "zh-CN",
      )

    assert_equal "你好", out
    assert_equal 1, provider.requests.length

    req = provider.requests.first
    assert_equal "m1", req.fetch(:model)
    assert_nil req.fetch(:tools)
    assert_equal 0, req.fetch(:options).fetch(:temperature)

    system_msg = req.fetch(:messages).first
    assert system_msg.system?
    assert_includes system_msg.text, "Language Policy:"
    assert_includes system_msg.text, "Rewrite the user's text into zh-CN."
  end

  test "rewrite rejects reserved keys in llm_options" do
    provider = FakeProvider.new(reply_text: "x")

    assert_raises(ArgumentError) do
      AgentCore::Contrib::LanguagePolicy::FinalRewriter.rewrite(
        provider: provider,
        model: "m1",
        text: "hello",
        target_lang: "zh-CN",
        llm_options: { model: "nope" },
      )
    end
  end

  test "rewrite skips when already in target language (conservative CJK detector)" do
    provider = FakeProvider.new(reply_text: "should not be called")

    out =
      AgentCore::Contrib::LanguagePolicy::FinalRewriter.rewrite(
        provider: provider,
        model: "m1",
        text: "你好",
        target_lang: "zh-CN",
      )

    assert_equal "你好", out
    assert_empty provider.requests
  end
end
