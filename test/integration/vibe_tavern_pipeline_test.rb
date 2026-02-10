require "test_helper"

class VibeTavernPipelineTest < ActiveSupport::TestCase
  test "builds a minimal plan with history + user message" do
    history = [
      TavernKit::PromptBuilder::Message.new(role: :user, content: "Hi"),
      TavernKit::PromptBuilder::Message.new(
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

  test "allows overriding the default system text builder via pipeline step options" do
    character = TavernKit::Character.create(name: "Seraphina", system_prompt: "SYS")
    user = TavernKit::User.new(name: "J", persona: "I like cats")

    pipeline = TavernKit::VibeTavern::Pipeline.dup
    pipeline.configure_step(
      :plan_assembly,
      default_system_text_builder: lambda do |ctx|
        "Custom System: #{ctx.character.name} / #{ctx.user.name}"
      end,
    )

    plan =
      TavernKit::PromptBuilder.build(pipeline: pipeline) do
        character character
        user user
        message "Hello."
      end

    msgs = plan.to_messages(dialect: :openai)

    assert_equal "system", msgs[0][:role]
    assert_equal "Custom System: Seraphina / J", msgs[0][:content]

    assert_equal "user", msgs[1][:role]
    assert_equal "Hello.", msgs[1][:content]
  end

  test "prepare step rejects unknown step config keys" do
    error =
      assert_raises(ArgumentError) do
        TavernKit::PromptBuilder.build(pipeline: TavernKit::VibeTavern::Pipeline) do
          context({ module_configs: { prepare: { typo: true } } })
          message "Hello."
        end
      end

    assert_match(/invalid config for step prepare/, error.message)
  end

  test "plan_assembly step rejects unknown step config keys" do
    error =
      assert_raises(ArgumentError) do
        TavernKit::PromptBuilder.build(pipeline: TavernKit::VibeTavern::Pipeline) do
          context({ module_configs: { plan_assembly: { typo: true } } })
          message "Hello."
        end
      end

    assert_match(/invalid config for step plan_assembly/, error.message)
  end

  test "optionally prepends a system block from system_template (Liquid-rendered)" do
    store = TavernKit::VariablesStore::InMemory.new
    store.set("mood", "happy", scope: :local)

    context = TavernKit::PromptBuilder::Context.build({ chat_index: 1, message_index: 5, rng_word: "seed" }, type: :app)
    character = TavernKit::Character.create(name: "Seraphina", nickname: "Sera")

    plan =
      TavernKit::VibeTavern.build do
        context context
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
      TavernKit::PromptBuilder::Message.new(role: :assistant, content: "Earlier..."),
      TavernKit::PromptBuilder::Message.new(role: :user, content: "Ok."),
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
      TavernKit::PromptBuilder::Message.new(role: :assistant, content: "Earlier..."),
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

  test "inserts a language policy system block after post_history_instructions and before the user message when enabled" do
    context = { language_policy: { enabled: true, target_lang: "zh-cn" } }
    pipeline = TavernKit::VibeTavern::Pipeline.dup
    pipeline.configure_step(
      :language_policy,
      **context.fetch(:language_policy),
    )

    character = TavernKit::Character.create(name: "Seraphina", post_history_instructions: "PHI")

    history = [
      TavernKit::PromptBuilder::Message.new(role: :assistant, content: "Earlier..."),
      TavernKit::PromptBuilder::Message.new(role: :user, content: "Ok."),
    ]

    plan =
      TavernKit::PromptBuilder.build(pipeline: pipeline) do
        character character
        meta :system_template, nil
        context context

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

    assert_equal "system", msgs[3][:role]
    assert_includes msgs[3][:content], "Language Policy:"
    assert_includes msgs[3][:content], "Respond in: zh-CN"

    assert_equal "user", msgs[4][:role]
    assert_equal "Continue.", msgs[4][:content]
  end

  test "canonicalizes base language tags (ja -> ja-JP) for target_lang allowlist checks" do
    context = { language_policy: { enabled: true, target_lang: "ja" } }
    pipeline = TavernKit::VibeTavern::Pipeline.dup
    pipeline.configure_step(
      :language_policy,
      **context.fetch(:language_policy),
    )

    plan =
      TavernKit::PromptBuilder.build(pipeline: pipeline) do
        meta :system_template, nil
        context context
        message "Hello."
      end

    msgs = plan.to_messages(dialect: :openai)
    lp = msgs.find { |m| m[:role] == "system" && m[:content].to_s.include?("Language Policy:") }
    refute_nil lp
    assert_includes lp[:content], "Respond in: ja-JP"
  end

  test "allows overriding the language policy text builder via pipeline step options" do
    context = { language_policy: { enabled: true, target_lang: "zh-CN", style_hint: "casual" } }
    pipeline = TavernKit::VibeTavern::Pipeline.dup
    pipeline.configure_step(
      :language_policy,
      **context.fetch(:language_policy),
      policy_text_builder: lambda do |target_lang, style_hint:, special_tags:|
        "Custom LP: #{target_lang} (style=#{style_hint.inspect}, tags=#{special_tags.join(",")})"
      end,
    )

    plan =
      TavernKit::PromptBuilder.build(pipeline: pipeline) do
        meta :system_template, nil
        context context
        message "Hello."
      end

    msgs = plan.to_messages(dialect: :openai)
    lp = msgs.find { |m| m[:role] == "system" && m[:content].to_s.include?("Custom LP:") }
    refute_nil lp
    assert_includes lp[:content], "Custom LP: zh-CN"
  end

  test "does not insert a language policy block when disabled" do
    context = { language_policy: { enabled: false, target_lang: "zh-CN" } }
    pipeline = TavernKit::VibeTavern::Pipeline.dup
    pipeline.configure_step(
      :language_policy,
      **context.fetch(:language_policy),
    )

    plan =
      TavernKit::PromptBuilder.build(pipeline: pipeline) do
        meta :system_template, nil
        context context
        message "Hello."
      end

    msgs = plan.to_messages(dialect: :openai)
    assert_equal ["user"], msgs.map { |m| m[:role] }
  end

  test "normalizes context input once and ensures variables_store exists" do
    context_data = TavernKit::PromptBuilder::Context.build({ "chatIndex" => 1, :message_index => 2 }, type: :app).to_h
    context = TavernKit::PromptBuilder::Context.new(context_data.merge(user_message: "Hello"), type: :app)
    state = TavernKit::PromptBuilder::State.new(context: context)

    TavernKit::VibeTavern::Pipeline.call(state)

    assert_instance_of TavernKit::PromptBuilder::Context, state.context
    assert_equal :app, state.context.type
    assert_equal 1, state.context[:chat_index]
    assert_equal 2, state.context[:message_index]

    assert_instance_of TavernKit::VariablesStore::InMemory, state.variables_store
  end

  test "token_estimation context config can set model_hint and token_estimator registry" do
    context = TavernKit::PromptBuilder::Context.new(
      user_message: "Hello",
      token_estimation: {
        model_hint: "llama-3.1",
        registry: {
          "llama-3.1" => { tokenizer_family: :heuristic, chars_per_token: 2.0 },
        },
      },
    )
    state = TavernKit::PromptBuilder::State.new(context: context)

    TavernKit::VibeTavern::Pipeline.call(state)

    assert_equal "llama-3.1", state[:model_hint]
    assert_equal :context, state[:model_hint_source]
    assert_equal :context_registry, state[:token_estimator_source]

    info = state.token_estimator.describe(model_hint: state[:model_hint])
    assert_equal "heuristic", info[:backend]
    assert_equal true, info[:registry]
  end

  test "sets model_hint from default_model_hint when explicit hint is absent" do
    state = TavernKit::PromptBuilder::State.new(user_message: "Hello")
    state[:default_model_hint] = "gpt-4"

    TavernKit::VibeTavern::Pipeline.call(state)

    assert_equal "gpt-4", state[:model_hint]
    assert_equal :default, state[:model_hint_source]
  end

  test "explicit model_hint wins over token_estimation context hint" do
    context = TavernKit::PromptBuilder::Context.new(user_message: "Hello", token_estimation: { model_hint: "context" })
    state = TavernKit::PromptBuilder::State.new(context: context)
    state[:model_hint] = "explicit"

    TavernKit::VibeTavern::Pipeline.call(state)

    assert_equal "explicit", state[:model_hint]
  end

  test "token_estimation metadata fallback is not used without context config" do
    state = TavernKit::PromptBuilder::State.new(user_message: "Hello")
    state[:token_estimation] = {
      model_hint: "metadata-only",
      registry: {
        "metadata-only" => { tokenizer_family: :heuristic, chars_per_token: 2.0 },
      },
    }

    TavernKit::VibeTavern::Pipeline.call(state)

    assert_nil state[:model_hint_source]
    assert_nil state[:token_estimator_source]
    refute_equal "metadata-only", state[:model_hint]
  end
end
