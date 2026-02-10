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

  def test_trace_collector_records_stages_and_warnings
    collector = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new
    state = TavernKit::PromptBuilder::State.new(warning_handler: nil)
    state.instrumenter = collector

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step WarnA, name: :a
      use_step WarnB, name: :b
    end

    pipeline.call(state)

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:a, :b], trace.stages.map(&:name)
    assert_equal ["a", "b"], trace.total_warnings
    assert_equal ["a"], trace.stages[0].warnings
    assert_equal 1, trace.stages[0].stats[:a_count]
  end

  def test_pipeline_error_wraps_stage_and_preserves_cause
    collector = TavernKit::PromptBuilder::Instrumenter::TraceCollector.new
    state = TavernKit::PromptBuilder::State.new(warning_handler: nil)
    state.instrumenter = collector

    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step WarnA, name: :a
      use_step Boom, name: :boom
    end

    error = assert_raises(TavernKit::PipelineError) { pipeline.call(state) }
    assert_equal :boom, error.stage
    assert_equal RuntimeError, error.cause.class

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:a, :boom], trace.stages.map(&:name)
    refute trace.success?
  end
end
