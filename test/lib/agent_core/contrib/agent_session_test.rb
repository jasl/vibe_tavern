# frozen_string_literal: true

require "test_helper"
require "json"

class AgentCoreContribAgentSessionTest < ActiveSupport::TestCase
  class FakeProvider < AgentCore::Resources::Provider::Base
    attr_reader :requests

    def initialize(replies:)
      @replies = Array(replies).dup
      @requests = []
    end

    def name = "fake"

    def chat(messages:, model:, tools: nil, stream: false, **options)
      raise ArgumentError, "expected stream=false" if stream

      @requests << { messages: messages, model: model, tools: tools, options: options }

      reply = @replies.shift
      reply = "" if reply.nil?

      AgentCore::Resources::Provider::Response.new(
        message: AgentCore::Message.new(role: :assistant, content: reply),
        usage: nil,
        raw: nil,
        stop_reason: :end_turn,
      )
    end
  end

  test "chat returns core run_result when language policy disabled" do
    provider = FakeProvider.new(replies: ["hello"])

    session =
      AgentCore::Contrib::AgentSession.new(
        provider: provider,
        model: "m1",
        system_prompt: "",
        history: [{ role: "assistant", content: "prev" }],
        llm_options: { temperature: 0.2 },
      )

    result = session.chat("hi")
    assert_equal "hello", result.text
    assert_equal 1, provider.requests.length
  end

  test "chat rewrites final text when language policy enabled" do
    provider = FakeProvider.new(replies: ["hello", "你好"])

    session =
      AgentCore::Contrib::AgentSession.new(
        provider: provider,
        model: "m1",
        system_prompt: "",
        history: [],
        llm_options: {},
      )

    result = session.chat("hi", language_policy: { enabled: true, target_lang: "zh-CN" })

    assert_equal "你好", result.text
    assert_equal "你好", result.final_message.text
    assert_equal "你好", result.messages.last.text
    assert_equal 2, provider.requests.length
  end

  test "directives rewrites assistant_text only (directives payload preserved)" do
    envelope = { assistant_text: "hello", directives: [{ type: "noop", payload: { "x" => 1 } }] }
    provider = FakeProvider.new(replies: [JSON.generate(envelope), "你好"])

    session =
      AgentCore::Contrib::AgentSession.new(
        provider: provider,
        model: "m1",
        system_prompt: "",
        history: [{ role: "user", content: "hi" }],
        llm_options: {},
      )

    result = session.directives(language_policy: { enabled: true, target_lang: "zh-CN" })

    assert_equal true, result.fetch(:ok)
    assert_equal "你好", result.fetch(:assistant_text)

    directives = result.fetch(:directives)
    assert_equal 1, directives.length
    assert_equal "noop", directives.first.fetch("type")
    assert_equal({ "x" => 1 }, directives.first.fetch("payload"))

    envelope_out = result.fetch(:envelope)
    assert_equal "你好", envelope_out.fetch("assistant_text")
    assert_equal 2, provider.requests.length
  end

  test "chat_stream emits final-only events when language policy enabled" do
    provider = FakeProvider.new(replies: ["hello", "你好"])

    session =
      AgentCore::Contrib::AgentSession.new(
        provider: provider,
        model: "m1",
        system_prompt: "",
        history: [],
        llm_options: {},
      )

    events = []
    session.chat_stream("hi", language_policy: { enabled: true, target_lang: "zh-CN" }) do |event|
      events << event
    end

    assert_equal 3, events.length
    assert_equal :text_delta, events[0].type
    assert_equal "你好", events[0].text
    assert_equal :message_complete, events[1].type
    assert_equal :done, events[2].type
  end
end
