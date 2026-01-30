# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::DSLTest < Minitest::Test
  # Simple middleware that creates a plan from context
  class SimplePlanMiddleware < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      blocks = []
      if ctx.user_message
        blocks << TavernKit::Prompt::Block.new(role: :user, content: ctx.user_message)
      end
      ctx.plan = TavernKit::Prompt::Plan.new(blocks: blocks)
    end
  end

  class DialectPlanMiddleware < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      ctx.plan = TavernKit::Prompt::Plan.new(
        blocks: [
          TavernKit::Prompt::Block.new(role: :user, content: ctx.dialect.to_s),
        ],
      )
    end
  end

  def simple_pipeline
    TavernKit::Prompt::Pipeline.new do
      use SimplePlanMiddleware, name: :simple
    end
  end

  def dialect_pipeline
    TavernKit::Prompt::Pipeline.new do
      use DialectPlanMiddleware, name: :dialect
    end
  end

  def test_dsl_requires_pipeline
    assert_raises(ArgumentError) do
      TavernKit::Prompt::DSL.new(pipeline: nil)
    end
  end

  def test_dsl_block_style
    pipeline = simple_pipeline
    plan = TavernKit::Prompt::DSL.build(pipeline: pipeline) do
      message "Hello!"
    end

    assert_kind_of TavernKit::Prompt::Plan, plan
    assert_equal 1, plan.size
    assert_equal "Hello!", plan.blocks.first.content
  end

  def test_dsl_fluent_style
    pipeline = simple_pipeline
    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)
    dsl.message("Hello!")
    plan = dsl.build

    assert_kind_of TavernKit::Prompt::Plan, plan
    assert_equal "Hello!", plan.blocks.first.content
  end

  def test_dsl_setters_return_self
    pipeline = simple_pipeline
    char = TavernKit::Character.create(name: "Test")
    user = TavernKit::User.new(name: "Alice")

    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)
    result = dsl.character(char)
    assert_same dsl, result

    result = dsl.user(user)
    assert_same dsl, result

    result = dsl.message("Hello!")
    assert_same dsl, result
  end

  def test_dsl_cannot_build_twice
    pipeline = simple_pipeline
    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)
    dsl.message("Hello!")
    dsl.build

    assert_raises(RuntimeError) { dsl.build }
  end

  def test_dsl_sets_context_fields
    pipeline = simple_pipeline
    char = TavernKit::Character.create(name: "Test")
    user = TavernKit::User.new(name: "Alice")

    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)
    dsl.character(char)
    dsl.user(user)
    dsl.dialect(:text)
    dsl.message("Hello!")
    dsl.generation_type(:continue)
    dsl.strict(true)

    ctx = dsl.context
    assert_equal char, ctx.character
    assert_equal user, ctx.user
    assert_equal :text, ctx.dialect
    assert_equal "Hello!", ctx.user_message
    assert_equal :continue, ctx.generation_type
    assert_equal true, ctx.strict
  end

  def test_dsl_sets_instrumenter
    collector = TavernKit::Prompt::Instrumenter::TraceCollector.new

    pipeline = simple_pipeline
    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)
    dsl.instrumenter(collector)
    dsl.warning_handler(nil)
    dsl.message("Hello!")
    dsl.build

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:simple], trace.stages.map(&:name)
  end

  def test_dsl_macro_vars
    pipeline = simple_pipeline
    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)
    dsl.macro_vars({ "MyVar" => "value" })

    assert_equal({ myvar: "value" }, dsl.context.macro_vars)
  end

  def test_dsl_set_var
    pipeline = simple_pipeline
    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)
    dsl.set_var("MyVar", "value")

    assert_equal "value", dsl.context.macro_vars[:myvar]
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

    assert_kind_of TavernKit::Prompt::Plan, plan
    assert_equal 1, plan.size
  end

  def test_dsl_to_messages_sets_ctx_dialect_before_build
    pipeline = dialect_pipeline
    dsl = TavernKit::Prompt::DSL.new(pipeline: pipeline)

    output = dsl.to_messages(dialect: :text)

    assert_equal :text, dsl.context.dialect
    assert_equal "text", output.first.fetch(:content)
  end

  def test_tavern_kit_to_messages_sets_ctx_dialect_before_build
    pipeline = dialect_pipeline
    output = TavernKit.to_messages(dialect: :text, pipeline: pipeline) { }

    assert_equal "text", output.first.fetch(:content)
  end
end
