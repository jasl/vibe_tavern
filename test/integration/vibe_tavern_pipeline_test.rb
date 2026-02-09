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

  test "builds a default system block from character/user when no system_template override is provided" do
    character =
      TavernKit::Character.create(
        name: "Seraphina",
        nickname: "Sera",
        system_prompt: "SYS",
        description: "Desc",
        personality: "Pers",
        scenario: "Scene",
      )
    user = TavernKit::User.new(name: "J", persona: "I like cats")

    plan =
      TavernKit::VibeTavern.build do
        character character
        user user
        message "Hello."
      end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "system", msgs[0][:role]
    assert_equal "SYS\n\nYou are Sera.\n\nDesc\n\nPers\n\nScenario:\nScene\n\nUser persona:\nI like cats", msgs[0][:content]

    assert_equal "user", msgs[1][:role]
    assert_equal "Hello.", msgs[1][:content]
  end

  test "optionally prepends a system block from system_template (Liquid-rendered)" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    runtime = TavernKit::Runtime::Base.build({ chat_index: 1, message_index: 5, rng_word: "seed" }, type: :app)
    character = TavernKit::Character.create(name: "Seraphina", nickname: "Sera")

    plan =
      TavernKit::VibeTavern.build do
        runtime runtime
        variables_store store
        character character

        meta :system_template, %(You are {{ char }}. Mood={{ var.mood }} Pick={{ "a,b,c" | pick }}.)
        message "Hello."
      end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "system", msgs[0][:role]
    assert_equal "You are Sera. Mood=happy Pick=a.", msgs[0][:content]
    assert_equal "user", msgs[1][:role]
    assert_equal "Hello.", msgs[1][:content]
  end

  test "allows explicitly disabling the system block via system_template override" do
    character = TavernKit::Character.create(name: "Seraphina")

    plan =
      TavernKit::VibeTavern.build do
        character character
        meta :system_template, nil
        message "Hello."
      end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "user", msgs[0][:role]
    assert_equal "Hello.", msgs[0][:content]
  end

  test "inserts post_history_instructions after history by default" do
    character = TavernKit::Character.create(name: "Seraphina", post_history_instructions: "PHI")

    history = [
      TavernKit::Prompt::Message.new(role: :assistant, content: "Earlier..."),
      TavernKit::Prompt::Message.new(role: :user, content: "Ok."),
    ]

    plan =
      TavernKit::VibeTavern.build do
        character character
        meta :system_template, nil

        history history
        message "Continue."
      end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "assistant", msgs[0][:role]
    assert_equal "Earlier...", msgs[0][:content]

    assert_equal "user", msgs[1][:role]
    assert_equal "Ok.", msgs[1][:content]

    assert_equal "system", msgs[2][:role]
    assert_equal "PHI", msgs[2][:content]

    assert_equal "user", msgs[3][:role]
    assert_equal "Continue.", msgs[3][:content]
  end

  test "supports post_history_template override (Liquid-rendered) and can suppress default post_history_instructions" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    character = TavernKit::Character.create(name: "Seraphina", post_history_instructions: "PHI")

    history = [
      TavernKit::Prompt::Message.new(role: :assistant, content: "Earlier..."),
    ]

    plan =
      TavernKit::VibeTavern.build do
        variables_store store
        character character
        meta :system_template, nil
        meta :post_history_template, %(Mood={{ var.mood }})

        history history
        message "Continue."
      end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "assistant", msgs[0][:role]
    assert_equal "Earlier...", msgs[0][:content]

    assert_equal "system", msgs[1][:role]
    assert_equal "Mood=happy", msgs[1][:content]

    assert_equal "user", msgs[2][:role]
    assert_equal "Continue.", msgs[2][:content]

    plan2 =
      TavernKit::VibeTavern.build do
        character character
        meta :system_template, nil
        meta :post_history_template, nil

        history history
        message "Continue."
      end

    msgs2 = plan2.to_messages(dialect: :openai)
    assert_equal %w[assistant user], msgs2.map { |m| m[:role] }
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

  test "token_estimation runtime config can set model_hint and token_estimator registry" do
    ctx = TavernKit::Prompt::Context.new(user_message: "Hello")
    ctx[:runtime] = {
      token_estimation: {
        model_hint: "llama-3.1",
        registry: {
          "llama-3.1" => { tokenizer_family: :heuristic, chars_per_token: 2.0 },
        },
      },
    }

    TavernKit::VibeTavern::Pipeline.call(ctx)

    assert_equal "llama-3.1", ctx[:model_hint]
    assert_equal :runtime, ctx[:model_hint_source]
    assert_equal :runtime_registry, ctx[:token_estimator_source]

    info = ctx.token_estimator.describe(model_hint: ctx[:model_hint])
    assert_equal "heuristic", info[:backend]
    assert_equal true, info[:registry]
  end

  test "sets model_hint from default_model_hint when explicit hint is absent" do
    ctx = TavernKit::Prompt::Context.new(user_message: "Hello")
    ctx[:default_model_hint] = "gpt-4"

    TavernKit::VibeTavern::Pipeline.call(ctx)

    assert_equal "gpt-4", ctx[:model_hint]
    assert_equal :default, ctx[:model_hint_source]
  end

  test "explicit model_hint wins over token_estimation runtime hint" do
    ctx = TavernKit::Prompt::Context.new(user_message: "Hello")
    ctx[:model_hint] = "explicit"
    ctx[:runtime] = { token_estimation: { model_hint: "runtime" } }

    TavernKit::VibeTavern::Pipeline.call(ctx)

    assert_equal "explicit", ctx[:model_hint]
  end
end
