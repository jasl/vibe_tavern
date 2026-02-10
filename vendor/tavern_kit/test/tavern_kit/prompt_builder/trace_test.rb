# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::TraceTest < Minitest::Test
  class WarnA < TavernKit::PromptBuilder::Step
    private

    def before(ctx)
      ctx.warn("a")
      ctx.instrument(:stat, key: :a_count, value: 1)
    end
  end

  class WarnB < TavernKit::PromptBuilder::Step
    private

    def before(ctx)
      ctx.warn("b")
    end
  end

  class Boom < TavernKit::PromptBuilder::Step
    private

    def before(_ctx)
      raise "boom"
    end
  end

  def test_trace_collector_records_steps_and_warnings
    collector = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new
    state = TavernKit::PromptBuilder::State.new(warning_handler: nil)
    state.instrumenter = collector

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :a, WarnA
      use_step :b, WarnB
    end

    pipeline.call(state)

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:a, :b], trace.steps.map(&:name)
    assert_equal ["a", "b"], trace.total_warnings
    assert_equal ["a"], trace.steps[0].warnings
    assert_equal 1, trace.steps[0].stats[:a_count]
  end

  def test_pipeline_error_wraps_step_and_preserves_cause
    collector = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new
    state = TavernKit::PromptBuilder::State.new(warning_handler: nil)
    state.instrumenter = collector

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :a, WarnA
      use_step :boom, Boom
    end

    error = assert_raises(TavernKit::PipelineError) { pipeline.call(state) }
    assert_equal :boom, error.step
    assert_equal RuntimeError, error.cause.class

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:a, :boom], trace.steps.map(&:name)
    refute trace.success?
  end

  def test_trace_collector_rejects_mismatched_step_finish
    collector = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new
    collector.call(:step_start, name: :a)

    assert_raises(ArgumentError) do
      collector.call(:step_finish, name: :b)
    end
  end
end
