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

  class CaptureOptionsStep < TavernKit::PromptBuilder::Step
    private

    def before(ctx)
      ctx[:captured_options] = options
    end
  end

  class TypedConfigStep < TavernKit::PromptBuilder::Step
    Config =
      Data.define(:label) do
        def self.from_hash(raw)
          raise ArgumentError, "typed config must be a Hash" unless raw.is_a?(Hash)

          raw.each_key do |key|
            raise ArgumentError, "typed config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          label = raw.fetch(:label).to_s.strip
          raise ArgumentError, "typed config requires :label" if label.empty?

          new(label: label)
        end
      end

    private

    def before(ctx)
      cfg = options.fetch(:config)
      ctx[:typed_config] = cfg
      ctx[:typed_label] = cfg.label
    end
  end

  def test_empty_pipeline
    pipeline = TavernKit::PromptBuilder::Pipeline.empty
    assert pipeline.empty?
    assert_equal 0, pipeline.size
  end

  def test_use_step_adds_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
    end
    assert_equal 1, pipeline.size
    assert_equal [:alpha], pipeline.names
    assert pipeline.has?(:alpha)
  end

  def test_pipeline_execution_order
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :first, RecordStep, label: :first
      use_step :second, RecordStep, label: :second
    end

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)

    # Before hooks in forward order, after hooks in reverse order
    assert_equal [:before_first, :before_second, :after_second, :after_first], state[:calls]
  end

  def test_replace_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :step, AlphaStep
    end
    pipeline.replace_step(:step, BetaStep)

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)
    assert_equal [:beta], state[:calls]
  end

  def test_insert_before
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
    end
    pipeline.insert_step_before(:alpha, BetaStep, name: :beta)

    assert_equal [:beta, :alpha], pipeline.names

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)
    assert_equal [:beta, :alpha], state[:calls]
  end

  def test_insert_after
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
    end
    pipeline.insert_step_after(:alpha, BetaStep, name: :beta)

    assert_equal [:alpha, :beta], pipeline.names
  end

  def test_remove_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
      use_step :beta, BetaStep
    end
    pipeline.remove_step(:alpha)

    assert_equal [:beta], pipeline.names
    refute pipeline.has?(:alpha)
  end

  def test_configure_step
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :step, RecordStep, label: :original
    end
    pipeline.configure_step(:step, label: :updated)

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)
    assert_equal [:before_updated, :after_updated], state[:calls]
  end

  def test_context_module_configs_deep_merge_step_options
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step(
        :capture,
        CaptureOptionsStep,
        nested: { keep: :base, override: :base },
        scalar: :base,
        list: [1, 2],
      )
    end

    context =
      TavernKit::PromptBuilder::Context.new(
        module_configs: {
          capture: {
            nested: { override: :context },
            scalar: :context,
            list: [9],
          },
        },
      )
    state = TavernKit::PromptBuilder::State.new(context: context)

    pipeline.call(state)

    assert_equal(
      {
        nested: { keep: :base, override: :context },
        scalar: :context,
        list: [9],
        __step: :capture,
      },
      state[:captured_options],
    )
  end

  def test_context_module_configs_unknown_step_is_ignored
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
    end

    context =
      TavernKit::PromptBuilder::Context.new(
        module_configs: {
          unknown_step: { enabled: true },
        },
      )
    state = TavernKit::PromptBuilder::State.new(context: context, strict: true, warning_handler: nil)
    pipeline.call(state)

    assert_equal [:alpha], state[:calls]
    assert_equal [], state.warnings
  end

  def test_step_config_class_is_parsed_from_default_options
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :typed, TypedConfigStep, label: :base
    end

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)

    assert_instance_of TypedConfigStep::Config, state[:typed_config]
    assert_equal "base", state[:typed_label]
  end

  def test_step_config_class_is_parsed_after_context_override
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :typed, TypedConfigStep, label: :base
    end

    context =
      TavernKit::PromptBuilder::Context.new(
        module_configs: {
          typed: { label: :override },
        },
      )
    state = TavernKit::PromptBuilder::State.new(context: context)
    pipeline.call(state)

    assert_instance_of TypedConfigStep::Config, state[:typed_config]
    assert_equal "override", state[:typed_label]
  end

  def test_step_config_class_raises_on_invalid_config
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :typed, TypedConfigStep, label: :base
    end

    context =
      TavernKit::PromptBuilder::Context.new(
        module_configs: {
          typed: { label: "" },
        },
      )
    state = TavernKit::PromptBuilder::State.new(context: context)

    error = assert_raises(ArgumentError) { pipeline.call(state) }
    assert_match(/invalid config for step typed/, error.message)
  end

  def test_duplicate_name_raises
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :step, AlphaStep
    end
    assert_raises(ArgumentError) do
      pipeline.use_step(:step, BetaStep)
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
      use_step :alpha, AlphaStep
    end
    copy = original.dup
    copy.use_step(:beta, BetaStep)

    assert_equal [:alpha], original.names
    assert_equal [:alpha, :beta], copy.names
  end

  def test_bracket_access
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
    end
    entry = pipeline[:alpha]
    assert_equal :alpha, entry.name
    assert_equal AlphaStep, entry.step_class

    assert_nil pipeline[:unknown]
  end

  def test_enumerable
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
      use_step :beta, BetaStep
    end
    names = pipeline.map(&:name)
    assert_equal [:alpha, :beta], names
  end
end
