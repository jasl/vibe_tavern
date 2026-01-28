# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::PipelineTest < Minitest::Test
  # Test middleware that records calls
  class RecordMiddleware < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      ctx[:calls] ||= []
      ctx[:calls] << :"before_#{options[:label]}"
    end

    def after(ctx)
      ctx[:calls] ||= []
      ctx[:calls] << :"after_#{options[:label]}"
    end
  end

  class AlphaMiddleware < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      ctx[:calls] ||= []
      ctx[:calls] << :alpha
    end
  end

  class BetaMiddleware < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      ctx[:calls] ||= []
      ctx[:calls] << :beta
    end
  end

  def test_empty_pipeline
    pipeline = TavernKit::Prompt::Pipeline.empty
    assert pipeline.empty?
    assert_equal 0, pipeline.size
  end

  def test_use_adds_middleware
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :alpha
    end
    assert_equal 1, pipeline.size
    assert_equal [:alpha], pipeline.names
    assert pipeline.has?(:alpha)
  end

  def test_pipeline_execution_order
    pipeline = TavernKit::Prompt::Pipeline.new do
      use RecordMiddleware, name: :first, label: :first
      use RecordMiddleware, name: :second, label: :second
    end

    ctx = TavernKit::Prompt::Context.new
    pipeline.call(ctx)

    # Before hooks in forward order, after hooks in reverse order
    assert_equal [:before_first, :before_second, :after_second, :after_first], ctx[:calls]
  end

  def test_replace_middleware
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :step
    end
    pipeline.replace(:step, BetaMiddleware)

    ctx = TavernKit::Prompt::Context.new
    pipeline.call(ctx)
    assert_equal [:beta], ctx[:calls]
  end

  def test_insert_before
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :alpha
    end
    pipeline.insert_before(:alpha, BetaMiddleware, name: :beta)

    assert_equal [:beta, :alpha], pipeline.names

    ctx = TavernKit::Prompt::Context.new
    pipeline.call(ctx)
    assert_equal [:beta, :alpha], ctx[:calls]
  end

  def test_insert_after
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :alpha
    end
    pipeline.insert_after(:alpha, BetaMiddleware, name: :beta)

    assert_equal [:alpha, :beta], pipeline.names
  end

  def test_remove_middleware
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :alpha
      use BetaMiddleware, name: :beta
    end
    pipeline.remove(:alpha)

    assert_equal [:beta], pipeline.names
    refute pipeline.has?(:alpha)
  end

  def test_configure_middleware
    pipeline = TavernKit::Prompt::Pipeline.new do
      use RecordMiddleware, name: :step, label: :original
    end
    pipeline.configure(:step, label: :updated)

    ctx = TavernKit::Prompt::Context.new
    pipeline.call(ctx)
    assert_equal [:before_updated, :after_updated], ctx[:calls]
  end

  def test_duplicate_name_raises
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :step
    end
    assert_raises(ArgumentError) do
      pipeline.use(BetaMiddleware, name: :step)
    end
  end

  def test_unknown_middleware_raises
    pipeline = TavernKit::Prompt::Pipeline.empty
    assert_raises(ArgumentError) { pipeline.replace(:unknown, AlphaMiddleware) }
    assert_raises(ArgumentError) { pipeline.remove(:unknown) }
    assert_raises(ArgumentError) { pipeline.insert_before(:unknown, AlphaMiddleware) }
    assert_raises(ArgumentError) { pipeline.insert_after(:unknown, AlphaMiddleware) }
  end

  def test_dup_creates_independent_copy
    original = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :alpha
    end
    copy = original.dup
    copy.use(BetaMiddleware, name: :beta)

    assert_equal [:alpha], original.names
    assert_equal [:alpha, :beta], copy.names
  end

  def test_bracket_access
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :alpha
    end
    entry = pipeline[:alpha]
    assert_equal :alpha, entry.name
    assert_equal AlphaMiddleware, entry.middleware

    assert_nil pipeline[:unknown]
  end

  def test_enumerable
    pipeline = TavernKit::Prompt::Pipeline.new do
      use AlphaMiddleware, name: :alpha
      use BetaMiddleware, name: :beta
    end
    names = pipeline.map(&:name)
    assert_equal [:alpha, :beta], names
  end
end
