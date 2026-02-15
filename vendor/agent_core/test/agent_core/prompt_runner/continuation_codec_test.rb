# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptRunner::ContinuationCodecTest < Minitest::Test
  def setup
    @runner = AgentCore::PromptRunner::Runner.new
    @allow_all = AgentCore::Resources::Tools::Policy::AllowAll.new
  end

  def test_round_trip_json_for_awaiting_tool_results
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      )

    assert paused.awaiting_tool_results?

    payload = AgentCore::PromptRunner::ContinuationCodec.dump(paused.continuation, include_traces: false)
    refute payload.key?("turn_traces")

    json = JSON.generate(payload)
    parsed = JSON.parse(json)
    loaded = AgentCore::PromptRunner::ContinuationCodec.load(parsed)

    assert_equal paused.run_id, loaded.run_id
    assert_equal :awaiting_tool_results, loaded.pause_reason

    resumed =
      @runner.resume_with_tool_results(
        continuation: loaded,
        tool_results: { "tc_1" => AgentCore::Resources::Tools::ToolResult.success(text: "ok") },
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
      )

    assert_equal "Done", resumed.text
  end

  def test_round_trip_json_for_awaiting_tool_confirmation
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    final_msg = AgentCore::Message.new(role: :assistant, content: "Done")
    final_response = AgentCore::Resources::Provider::Response.new(message: final_msg, stop_reason: :end_turn)

    provider = MockProvider.new(responses: [tool_response, final_response])

    executed = 0
    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        executed += 1
        AgentCore::Resources::Tools::ToolResult.success(text: "ok")
      end
    )

    policy =
      Class.new(AgentCore::Resources::Tools::Policy::Base) do
        def authorize(name:, arguments: {}, context:)
          AgentCore::Resources::Tools::Policy::Decision.confirm(reason: "needs confirmation")
        end
      end.new

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: policy,
      )

    assert paused.awaiting_tool_confirmation?
    assert_equal 0, executed

    payload = AgentCore::PromptRunner::ContinuationCodec.dump(paused.continuation)
    loaded = AgentCore::PromptRunner::ContinuationCodec.load(JSON.generate(payload))

    resumed =
      @runner.resume(
        continuation: loaded,
        tool_confirmations: { "tc_1" => :allow },
        provider: provider,
        tools_registry: registry,
        tool_policy: policy,
      )

    assert_equal "Done", resumed.text
    assert_equal 1, executed
  end

  def test_schema_version_mismatch_raises
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    provider = MockProvider.new(responses: [tool_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
      )

    payload = AgentCore::PromptRunner::ContinuationCodec.dump(paused.continuation)
    payload["schema_version"] = 999

    assert_raises(ArgumentError) do
      AgentCore::PromptRunner::ContinuationCodec.load(payload)
    end
  end

  def test_context_attributes_allowlist_and_truncation
    tool_call = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { "text" => "hello" })
    assistant_with_tool = AgentCore::Message.new(role: :assistant, content: "Calling tool", tool_calls: [tool_call])
    tool_response = AgentCore::Resources::Provider::Response.new(message: assistant_with_tool, stop_reason: :tool_use)

    provider = MockProvider.new(responses: [tool_response])

    registry = AgentCore::Resources::Tools::Registry.new
    registry.register(
      AgentCore::Resources::Tools::Tool.new(name: "echo", description: "Echo", parameters: {}) do |_args, **|
        raise "should not execute inline"
      end
    )

    prompt = AgentCore::PromptBuilder::BuiltPrompt.new(
      system_prompt: "test",
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      tools: registry.definitions,
      options: { model: "test" }
    )

    paused =
      @runner.run(
        prompt: prompt,
        provider: provider,
        tools_registry: registry,
        tool_policy: @allow_all,
        tool_executor: AgentCore::PromptRunner::ToolExecutor::DeferAll.new,
        context: {
          tenant_id: "t_" + ("a" * 500),
          ignore_me: "nope",
        },
      )

    payload = AgentCore::PromptRunner::ContinuationCodec.dump(paused.continuation, context_keys: %i[tenant_id])
    attrs = payload.fetch("context_attributes")

    assert_equal ["tenant_id"], attrs.keys
    assert_operator attrs.fetch("tenant_id").bytesize, :<=, 200
  end
end
