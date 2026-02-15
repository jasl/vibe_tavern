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

  class ScriptedProvider < AgentCore::Resources::Provider::Base
    attr_reader :requests

    def initialize(responses:)
      @responses = Array(responses).dup
      @requests = []
    end

    def name = "scripted"

    def chat(messages:, model:, tools: nil, stream: false, **options)
      raise ArgumentError, "expected stream=false" if stream

      @requests << { messages: messages, model: model, tools: tools, options: options }

      response = @responses.shift
      raise "Unexpected provider call (no scripted response left)" unless response
      response
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

  test "resume continues after tool confirmation" do
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "dangerous", arguments: { "x" => 1 })
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done.")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = ScriptedProvider.new(responses: [tool_response, final_response])

    executed = []
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "dangerous", description: "bad", parameters: {}) do |_args, **|
        executed << true
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    confirm_policy = Class.new(AgentCore::Resources::Tools::Policy::Base) do
      def authorize(name:, arguments: {}, context: {})
        AgentCore::Resources::Tools::Policy::Decision.confirm(reason: "need approval")
      end
    end.new

    session =
      AgentCore::Contrib::AgentSession.new(
        provider: provider,
        model: "m1",
        system_prompt: "",
        history: [],
        tools_registry: registry,
        tool_policy: confirm_policy,
      )

    paused = session.chat("do something dangerous")
    assert paused.awaiting_tool_confirmation?
    assert_equal 0, executed.size

    resumed = session.resume(continuation: paused, tool_confirmations: { "tc_1" => :allow })

    assert_equal "Done.", resumed.text
    assert_equal paused.run_id, resumed.run_id
    assert_equal 1, executed.size
    assert_equal 2, provider.requests.length
  end

  test "tool_executor DeferAll pauses and resume_with_tool_results continues" do
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hi" })
    assistant_msg = AgentCore::Message.new(role: :assistant, content: "calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_msg, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done.")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = ScriptedProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    session =
      AgentCore::Contrib::AgentSession.new(
        provider: provider,
        model: "m1",
        system_prompt: "",
        history: [],
        tools_registry: registry,
        tool_policy: AgentCore::Resources::Tools::Policy::AllowAll.new,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      )

    paused = session.chat("hi")
    assert paused.awaiting_tool_results?
    assert_equal 1, paused.pending_tool_executions.size

    resumed =
      session.resume_with_tool_results(
        continuation: paused,
        tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") },
      )

    assert_equal "Done.", resumed.text
    assert_equal paused.run_id, resumed.run_id
    assert_equal 2, provider.requests.length
  end
end
