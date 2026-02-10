# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilderTest < Minitest::Test
  # Simple step that creates a plan from state
  class SimplePlanStep < TavernKit::PromptBuilder::Step
    private

    def before(ctx)
      blocks = []
      if ctx.user_message
        blocks << TavernKit::PromptBuilder::Block.new(role: :user, content: ctx.user_message)
      end
      ctx.plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)
    end
  end

  class DialectPlanStep < TavernKit::PromptBuilder::Step
    private

    def before(ctx)
      ctx.plan = TavernKit::PromptBuilder::Plan.new(
        blocks: [
          TavernKit::PromptBuilder::Block.new(role: :user, content: ctx.dialect.to_s),
        ],
      )
    end
  end

  def simple_pipeline
    TavernKit::PromptBuilder::Pipeline.new do
      use_step :simple, SimplePlanStep
    end
  end

  def dialect_pipeline
    TavernKit::PromptBuilder::Pipeline.new do
      use_step :dialect, DialectPlanStep
    end
  end

  def test_builder_requires_pipeline
    assert_raises(ArgumentError) do
      TavernKit::PromptBuilder.new(pipeline: nil)
    end
  end

  def test_builder_block_style
    pipeline = simple_pipeline
    plan = TavernKit::PromptBuilder.build(pipeline: pipeline) do
      message "Hello!"
    end

    assert_kind_of TavernKit::PromptBuilder::Plan, plan
    assert_equal 1, plan.size
    assert_equal "Hello!", plan.blocks.first.content
  end

  def test_builder_fluent_style
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    dsl.message("Hello!")
    plan = dsl.build

    assert_kind_of TavernKit::PromptBuilder::Plan, plan
    assert_equal "Hello!", plan.blocks.first.content
  end

  def test_builder_accepts_keyword_inputs
    pipeline = simple_pipeline
    char = TavernKit::Character.create(name: "Test")
    user = TavernKit::User.new(name: "Alice")

    dsl =
      TavernKit::PromptBuilder.new(
        pipeline: pipeline,
        character: char,
        user: user,
        message: "Hello!",
        strict: true,
      )

    assert_equal char, dsl.state.character
    assert_equal user, dsl.state.user
    assert_equal "Hello!", dsl.state.user_message
    assert_equal true, dsl.state.strict
  end

  def test_builder_rejects_unknown_keyword_input
    pipeline = simple_pipeline

    error =
      assert_raises(ArgumentError) do
        TavernKit::PromptBuilder.new(pipeline: pipeline, typo_key: true)
      end
    assert_match(/unknown PromptBuilder input key/, error.message)
  end

  def test_builder_configs_merges_into_context_module_configs
    pipeline = simple_pipeline
    context = TavernKit::PromptBuilder::Context.new(module_configs: { alpha: { enabled: true } })

    dsl =
      TavernKit::PromptBuilder.new(
        pipeline: pipeline,
        context: context,
        configs: { language_policy: { enabled: true } },
      )

    assert_equal(
      {
        alpha: { enabled: true },
        language_policy: { enabled: true },
      },
      dsl.state.context.module_configs,
    )
  end

  def test_builder_setters_return_self
    pipeline = simple_pipeline
    char = TavernKit::Character.create(name: "Test")
    user = TavernKit::User.new(name: "Alice")

    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    result = dsl.character(char)
    assert_same dsl, result

    result = dsl.user(user)
    assert_same dsl, result

    result = dsl.message("Hello!")
    assert_same dsl, result
  end

  def test_builder_cannot_build_twice
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    dsl.message("Hello!")
    dsl.build

    assert_raises(RuntimeError) { dsl.build }
  end

  def test_builder_sets_state_fields
    pipeline = simple_pipeline
    char = TavernKit::Character.create(name: "Test")
    user = TavernKit::User.new(name: "Alice")

    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    dsl.character(char)
    dsl.user(user)
    dsl.dialect(:text)
    dsl.message("Hello!")
    dsl.generation_type(:continue)
    dsl.strict(true)

    state = dsl.state
    assert_equal char, state.character
    assert_equal user, state.user
    assert_equal :text, state.dialect
    assert_equal "Hello!", state.user_message
    assert_equal :continue, state.generation_type
    assert_equal true, state.strict
  end

  def test_builder_sets_instrumenter
    collector = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new

    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    dsl.instrumenter(collector)
    dsl.warning_handler(nil)
    dsl.message("Hello!")
    dsl.build

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:simple], trace.steps.map(&:name)
  end

  def test_builder_macro_vars
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    dsl.macro_vars({ "MyVar" => "value" })

    assert_equal({ myvar: "value" }, dsl.state.macro_vars)
  end

  def test_builder_set_var
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    dsl.set_var("MyVar", "value")

    assert_equal "value", dsl.state.macro_vars[:myvar]
  end

  def test_builder_meta_sets_state_metadata
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    dsl.meta(:chat_index, 123)

    assert_equal 123, dsl.state[:chat_index]
  end

  def test_builder_variables_store_helpers
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)

    dsl.set_variable("x", "1")
    assert_kind_of TavernKit::VariablesStore::InMemory, dsl.state.variables_store
    assert_equal "1", dsl.state.variables_store.get("x", scope: :local)

    store = TavernKit::VariablesStore::InMemory.new
    dsl.variables_store(store)
    dsl.set_variables({ y: 2 }, scope: :global)
    assert_same store, dsl.state.variables_store
    assert_equal 2, store.get("y", scope: :global)
  end

  def test_builder_context_sets_input_context
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)
    context = { "chatIndex" => 7 }

    dsl.context(context)

    assert_instance_of TavernKit::PromptBuilder::Context, dsl.input_context
    assert_same dsl.input_context, dsl.state.context
    assert_equal 7, dsl.state.context[:chat_index]
    refute dsl.state.key?(:chat_index)
  end

  def test_builder_context_assignment_replaces_previous_context
    pipeline = simple_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)

    dsl.context(chat_index: 9)
    dsl.context(TavernKit::PromptBuilder::Context.new(user_message: "hello"))

    assert_nil dsl.state.context[:chat_index]
    assert_equal "hello", dsl.state.context[:user_message]
  end

  def test_initialize_with_context_does_not_project_context_to_state_metadata
    pipeline = simple_pipeline
    context = TavernKit::PromptBuilder::Context.new(chat_index: 11)
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline, context: context)

    assert_equal 11, dsl.state.context[:chat_index]
    refute dsl.state.key?(:chat_index)
  end

  def test_tavern_kit_build_requires_pipeline
    assert_raises(ArgumentError) do
      TavernKit.build(pipeline: nil) { message "Hello!" }
    end
  end

  def test_tavern_kit_build_with_pipeline
    pipeline = simple_pipeline
    plan = TavernKit.build(pipeline: pipeline) do
      message "Hello!"
    end

    assert_kind_of TavernKit::PromptBuilder::Plan, plan
    assert_equal 1, plan.size
  end

  def test_builder_to_messages_sets_state_dialect_before_build
    pipeline = dialect_pipeline
    dsl = TavernKit::PromptBuilder.new(pipeline: pipeline)

    output = dsl.to_messages(dialect: :text)

    assert_equal :text, dsl.state.dialect
    assert_equal "text", output.fetch(:prompt)
  end

  def test_tavern_kit_to_messages_sets_state_dialect_before_build
    pipeline = dialect_pipeline
    output = TavernKit.to_messages(dialect: :text, pipeline: pipeline) { }

    assert_equal "text", output.fetch(:prompt)
  end
end
