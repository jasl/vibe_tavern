# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::PipelineTest < Minitest::Test
  # Test step that records calls
  class RecordStep < TavernKit::PromptBuilder::Step
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

  class AlphaStep < TavernKit::PromptBuilder::Step
    private

    def before(ctx)
      ctx[:calls] ||= []
      ctx[:calls] << :alpha
    end
  end

  class BetaStep < TavernKit::PromptBuilder::Step
    private

    def before(ctx)
      ctx[:calls] ||= []
      ctx[:calls] << :beta
    end
  end

  def test_empty_pipeline
    pipeline = TavernKit::PromptBuilder::Pipeline.empty
    assert pipeline.empty?
    assert_equal 0, pipeline.size
  end

  def test_use_step_adds_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :alpha
    end
    assert_equal 1, pipeline.size
    assert_equal [:alpha], pipeline.names
    assert pipeline.has?(:alpha)
  end

  def test_pipeline_execution_order
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step RecordStep, name: :first, label: :first
      use_step RecordStep, name: :second, label: :second
    end

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)

    # Before hooks in forward order, after hooks in reverse order
    assert_equal [:before_first, :before_second, :after_second, :after_first], state[:calls]
  end

  def test_replace_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :step
    end
    pipeline.replace_step(:step, BetaStep)

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)
    assert_equal [:beta], state[:calls]
  end

  def test_insert_before
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :alpha
    end
    pipeline.insert_step_before(:alpha, BetaStep, name: :beta)

    assert_equal [:beta, :alpha], pipeline.names

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)
    assert_equal [:beta, :alpha], state[:calls]
  end

  def test_insert_after
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :alpha
    end
    pipeline.insert_step_after(:alpha, BetaStep, name: :beta)

    assert_equal [:alpha, :beta], pipeline.names
  end

  def test_remove_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :alpha
      use_step BetaStep, name: :beta
    end
    pipeline.remove_step(:alpha)

    assert_equal [:beta], pipeline.names
    refute pipeline.has?(:alpha)
  end

  def test_configure_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step RecordStep, name: :step, label: :original
    end
    pipeline.configure_step(:step, label: :updated)

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)
    assert_equal [:before_updated, :after_updated], state[:calls]
  end

  def test_duplicate_name_raises
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :step
    end
    assert_raises(ArgumentError) do
      pipeline.use_step(BetaStep, name: :step)
    end
  end

  def test_unknown_step_raises
    pipeline = TavernKit::PromptBuilder::Pipeline.empty
    assert_raises(ArgumentError) { pipeline.replace_step(:unknown, AlphaStep) }
    assert_raises(ArgumentError) { pipeline.remove_step(:unknown) }
    assert_raises(ArgumentError) { pipeline.insert_step_before(:unknown, AlphaStep) }
    assert_raises(ArgumentError) { pipeline.insert_step_after(:unknown, AlphaStep) }
  end

  def test_dup_creates_independent_copy
    original = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :alpha
    end
    copy = original.dup
    copy.use_step(BetaStep, name: :beta)

    assert_equal [:alpha], original.names
    assert_equal [:alpha, :beta], copy.names
  end

  def test_bracket_access
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :alpha
    end
    entry = pipeline[:alpha]
    assert_equal :alpha, entry.name
    assert_equal AlphaStep, entry.step_class

    assert_nil pipeline[:unknown]
  end

  def test_enumerable
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step AlphaStep, name: :alpha
      use_step BetaStep, name: :beta
    end
    names = pipeline.map(&:name)
    assert_equal [:alpha, :beta], names
  end
end
