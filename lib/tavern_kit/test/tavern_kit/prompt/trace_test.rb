# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::TraceTest < Minitest::Test
  class WarnA < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      ctx.warn("a")
      ctx.instrument(:stat, key: :a_count, value: 1)
    end
  end

  class WarnB < TavernKit::Prompt::Middleware::Base
    private

    def before(ctx)
      ctx.warn("b")
    end
  end

  class Boom < TavernKit::Prompt::Middleware::Base
    private

    def before(_ctx)
      raise "boom"
    end
  end

  def test_trace_collector_records_stages_and_warnings
    collector = TavernKit::Prompt::Instrumenter::TraceCollector.new
    ctx = TavernKit::Prompt::Context.new(warning_handler: nil)
    ctx.instrumenter = collector

    pipeline = TavernKit::Prompt::Pipeline.new do
      use WarnA, name: :a
      use WarnB, name: :b
    end

    pipeline.call(ctx)

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:a, :b], trace.stages.map(&:name)
    assert_equal ["a", "b"], trace.total_warnings
    assert_equal ["a"], trace.stages[0].warnings
    assert_equal 1, trace.stages[0].stats[:a_count]
  end

  def test_pipeline_error_wraps_stage_and_preserves_cause
    collector = TavernKit::Prompt::Instrumenter::TraceCollector.new
    ctx = TavernKit::Prompt::Context.new(warning_handler: nil)
    ctx.instrumenter = collector

    pipeline = TavernKit::Prompt::Pipeline.new do
      use WarnA, name: :a
      use Boom, name: :boom
    end

    error = assert_raises(TavernKit::PipelineError) { pipeline.call(ctx) }
    assert_equal :boom, error.stage
    assert_equal RuntimeError, error.cause.class

    trace = collector.to_trace(fingerprint: "fp")
    assert_equal [:a, :boom], trace.stages.map(&:name)
    refute trace.success?
  end
end
