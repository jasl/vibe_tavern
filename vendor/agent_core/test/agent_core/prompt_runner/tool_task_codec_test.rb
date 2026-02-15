# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptRunner::ToolTaskCodecTest < Minitest::Test
  def setup
    @runner = AgentCore::PromptRunner::Runner.new
    @allow_all = AgentCore::Resources::Tools::Policy::AllowAll.new
  end

  def test_dump_and_load_round_trip
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

    assert paused.awaiting_tool_results?

    payload = AgentCore::PromptRunner::ToolTaskCodec.dump(paused.continuation, context_keys: %i[tenant_id])

    assert_equal 1, payload.fetch("schema_version")
    assert_equal paused.run_id, payload.fetch("run_id")
    assert_equal 1, payload.fetch("turn_number")

    attrs = payload.fetch("context_attributes")
    assert_equal ["tenant_id"], attrs.keys
    assert_operator attrs.fetch("tenant_id").bytesize, :<=, 200

    tasks = payload.fetch("tasks")
    assert_equal 1, tasks.size
    assert_equal "tc_1", tasks[0].fetch("tool_call_id")
    assert_equal "echo", tasks[0].fetch("executed_name")

    json = JSON.generate(payload)
    loaded = AgentCore::PromptRunner::ToolTaskCodec.load(JSON.parse(json))

    assert_equal paused.run_id, loaded.run_id
    assert_equal 1, loaded.turn_number
    assert_equal 1, loaded.tasks.size
    assert_equal({ "text" => "hello" }, loaded.tasks.first.arguments)
    assert_equal [:tenant_id], loaded.context_attributes.keys
    assert_operator loaded.context_attributes.fetch(:tenant_id).bytesize, :<=, 200
  end
end
