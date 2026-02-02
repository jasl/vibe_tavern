require "test_helper"

class VibeTavernPipelineTest < ActiveSupport::TestCase
  test "builds a minimal plan with history + user message" do
    history = [
      TavernKit::Prompt::Message.new(role: :user, content: "Hi"),
      TavernKit::Prompt::Message.new(
        role: :assistant,
        content: "Hello!",
        metadata: { tool_calls: [{ id: "call_1", type: "function" }] },
      ),
    ]

    plan =
      TavernKit::VibeTavern.build do
        history history
        message "Continue."
      end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "user", msgs[0][:role]
    assert_equal "Hi", msgs[0][:content]

    assert_equal "assistant", msgs[1][:role]
    assert_equal "Hello!", msgs[1][:content]
    assert_equal [{ id: "call_1", type: "function" }], msgs[1][:tool_calls]

    assert_equal "user", msgs[2][:role]
    assert_equal "Continue.", msgs[2][:content]
  end

  test "normalizes runtime input once and ensures variables_store exists" do
    ctx = TavernKit::Prompt::Context.new(user_message: "Hello")
    ctx[:runtime] = { "chatIndex" => 1, :message_index => 2 }

    TavernKit::VibeTavern::Pipeline.call(ctx)

    assert_instance_of TavernKit::Runtime::Base, ctx.runtime
    assert_equal :app, ctx.runtime.type
    assert_equal 1, ctx.runtime[:chat_index]
    assert_equal 2, ctx.runtime[:message_index]

    assert_instance_of TavernKit::VariablesStore::InMemory, ctx.variables_store
  end
end
