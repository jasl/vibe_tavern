# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::PipelineTest < Minitest::Test
  # Test step that records calls
  module RecordStep
    extend TavernKit::PromptBuilder::Step

    Config =
      Data.define(:label) do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "record step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "record step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          unknown = raw.keys - %i[label]
          raise ArgumentError, "unknown record step config keys: #{unknown.inspect}" if unknown.any?

          label = raw.fetch(:label)
          new(label: label)
        end
      end

    def self.before(ctx, config)
      ctx[:calls] ||= []
      ctx[:calls] << :"before_#{config.label}"
    end

    def self.after(ctx, config)
      ctx[:calls] ||= []
      ctx[:calls] << :"after_#{config.label}"
    end
  end

  module AlphaStep
    extend TavernKit::PromptBuilder::Step

    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "alpha step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "alpha step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "alpha step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      ctx[:calls] ||= []
      ctx[:calls] << :alpha
    end
  end

  module BetaStep
    extend TavernKit::PromptBuilder::Step

    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "beta step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "beta step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "beta step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      ctx[:calls] ||= []
      ctx[:calls] << :beta
    end
  end

  module CaptureOptionsStep
    extend TavernKit::PromptBuilder::Step

    Config =
      Data.define(:nested, :scalar, :list) do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "capture options step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "capture options step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          unknown = raw.keys - %i[nested scalar list]
          raise ArgumentError, "unknown capture options step config keys: #{unknown.inspect}" if unknown.any?

          new(
            nested: raw.fetch(:nested),
            scalar: raw.fetch(:scalar),
            list: raw.fetch(:list),
          )
        end
      end

    def self.before(ctx, config)
      ctx[:captured_config] = config.to_h
    end
  end

  module TypedConfigStep
    extend TavernKit::PromptBuilder::Step

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

    def self.before(ctx, config)
      ctx[:typed_config] = config
      ctx[:typed_label] = config.label
    end
  end

  module NoInstantiateStep
    extend TavernKit::PromptBuilder::Step

    def self.new(*)
      raise "steps must not be instantiated"
    end

    Config =
      Data.define do
        def self.from_hash(raw)
          return raw if raw.is_a?(self)

          raise ArgumentError, "no_instantiate step config must be a Hash" unless raw.is_a?(Hash)
          raw.each_key do |key|
            raise ArgumentError, "no_instantiate step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          raise ArgumentError, "no_instantiate step does not accept step config keys: #{raw.keys.inspect}" if raw.any?

          new
        end
      end

    def self.before(ctx, _config)
      ctx[:calls] ||= []
      ctx[:calls] << :no_instantiate
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
    pipeline.insert_step_before(:alpha, :beta, BetaStep)

    assert_equal [:beta, :alpha], pipeline.names

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)
    assert_equal [:beta, :alpha], state[:calls]
  end

  def test_insert_after
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :alpha, AlphaStep
    end
    pipeline.insert_step_after(:alpha, :beta, BetaStep)

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
      },
      state[:captured_config],
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

  def test_pipeline_does_not_instantiate_steps
    pipeline = TavernKit::PromptBuilder::Pipeline.new do
      use_step :no_instantiate, NoInstantiateStep
    end

    state = TavernKit::PromptBuilder::State.new
    pipeline.call(state)

    assert_equal [:no_instantiate], state[:calls]
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
    assert_raises(ArgumentError) { pipeline.insert_step_before(:unknown, :beta, AlphaStep) }
    assert_raises(ArgumentError) { pipeline.insert_step_after(:unknown, :beta, AlphaStep) }
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
