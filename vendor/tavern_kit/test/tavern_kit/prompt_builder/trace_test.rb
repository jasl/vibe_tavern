# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::TraceTest < Minitest::Test
  class WarnA < TavernKit::PromptBuilder::Step
    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "warn_a step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "warn_a step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "warn_a step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      ctx.warn("a")
      ctx.instrument(:stat, key: :a_count, value: 1)
    end
  end

  class WarnB < TavernKit::PromptBuilder::Step
    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "warn_b step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "warn_b step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "warn_b step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      ctx.warn("b")
    end
  end

  class Boom < TavernKit::PromptBuilder::Step
    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "boom step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "boom step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "boom step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(_ctx, _config)
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
