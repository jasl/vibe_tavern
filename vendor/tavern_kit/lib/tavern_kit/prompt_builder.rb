# frozen_string_literal: true

require_relative "prompt_builder/context"
require_relative "prompt_builder/state"
require_relative "prompt_builder/step"
require_relative "prompt_builder/pipeline"

module TavernKit
  # PromptBuilder is the only public prompt-construction entrypoint.
  class PromptBuilder
    KEYWORD_INPUT_KEYS = %i[
      character
      user
      preset
      dialect
      history
      message
      lore_book
      lore_books
      generation_type
      group
      greeting
      authors_note
      macro_vars
      macro_registry
      injection_registry
      hook_registry
      force_world_info
      token_estimator
      variables_store
      lore_engine
      expander
      warning_handler
      instrumenter
      llm_options
      strict
    ].freeze

    attr_reader :state
    attr_reader :pipeline
    attr_reader :input_context

    def initialize(pipeline:, context: nil, configs: nil, **inputs, &block)
      raise ArgumentError, "pipeline: is required" if pipeline.nil?
      raise ArgumentError, "pipeline must be a TavernKit::PromptBuilder::Pipeline" unless pipeline.is_a?(Pipeline)

      @pipeline = pipeline
      @input_context = coerce_context(context)
      merge_configs!(configs) if configs
      @state = State.new(context: @input_context)
      @built = false
      apply_keyword_inputs!(inputs)

      instance_eval(&block) if block
    end

    def character(value)
      @state.character = value
      self
    end

    def user(value)
      @state.user = value
      self
    end

    def preset(value)
      @state.preset = value
      self
    end

    def dialect(value)
      @state.dialect = value&.to_sym
      self
    end

    def history(value)
      @state.history = value
      self
    end

    def message(text)
      @state.user_message = text.to_s
      self
    end

    def lore_book(book)
      @state.lore_books << book
      self
    end

    def lore_books(books)
      @state.lore_books.concat(Array(books))
      self
    end

    def generation_type(type)
      @state.generation_type = type
      self
    end

    def group(value)
      @state.group = value
      self
    end

    def greeting(index)
      @state.greeting_index = index
      self
    end

    def authors_note(position: nil, depth: nil, role: nil)
      overrides = {}
      overrides[:position] = position if position
      overrides[:depth] = depth if depth
      overrides[:role] = role if role
      @state.authors_note_overrides = overrides.empty? ? nil : overrides
      self
    end

    def macro_vars(vars)
      @state.macro_vars = vars&.transform_keys { |key| key.to_s.downcase.to_sym }
      self
    end

    def set_var(key, value)
      @state.macro_vars ||= {}
      @state.macro_vars[key.to_s.downcase.to_sym] = value
      self
    end

    def macro_registry(registry)
      @state.macro_registry = registry
      self
    end

    def injection_registry(registry)
      @state.injection_registry = registry
      self
    end

    def hook_registry(registry)
      @state.hook_registry = registry
      self
    end

    def force_world_info(activations)
      @state.forced_world_info_activations = Array(activations)
      self
    end

    def token_estimator(estimator)
      @state.token_estimator = estimator
      self
    end

    def variables_store(value)
      @state.variables_store = value
      self
    end

    def set_variable(name, value, scope: :local)
      @state.set_variable(name, value, scope: scope)
      self
    end

    def set_variables(hash, scope: :local)
      @state.set_variables(hash, scope: scope)
      self
    end

    def lore_engine(engine)
      @state.lore_engine = engine
      self
    end

    def expander(expander)
      @state.expander = expander
      self
    end

    def warning_handler(handler)
      @state.warning_handler = handler
      self
    end

    def meta(key, value)
      @state[key] = value
      self
    end

    # Set run context input object (or Hash that will be normalized).
    def context(value)
      @input_context = coerce_context(value)
      @state.context = @input_context
      self
    end

    # Merge per-step config overrides into context.module_configs.
    #
    # @param value [Hash]
    def configs(value)
      merge_configs!(value)
      @state.context = @input_context if @state
      self
    end

    def instrumenter(instrumenter)
      @state.instrumenter = instrumenter
      self
    end

    def llm_options(options)
      @state.llm_options = options
      self
    end

    def strict(enabled = true)
      @state.strict = enabled
      self
    end

    def configure_step(name, **options)
      @pipeline = @pipeline.dup
      @pipeline.configure_step(name, **options)
      self
    end

    def replace_step(name, step_class, **options)
      @pipeline = @pipeline.dup
      @pipeline.replace_step(name, step_class, **options)
      self
    end

    def insert_step_before(before_name, step_class, name: nil, **options)
      @pipeline = @pipeline.dup
      @pipeline.insert_step_before(before_name, step_class, name: name, **options)
      self
    end

    def insert_step_after(after_name, step_class, name: nil, **options)
      @pipeline = @pipeline.dup
      @pipeline.insert_step_after(after_name, step_class, name: name, **options)
      self
    end

    def remove_step(name)
      @pipeline = @pipeline.dup
      @pipeline.remove_step(name)
      self
    end

    def build
      raise "PromptBuilder has already been built" if @built

      @built = true
      @state.macro_vars ||= {}

      @pipeline.call(@state)
      @state.plan
    end

    def to_messages(dialect: :openai)
      self.dialect(dialect) if @state.dialect.nil?
      plan = build
      plan.to_messages(dialect: dialect)
    end

    class << self
      def build(pipeline:, context: nil, configs: nil, **kwargs, &block)
        builder = new(pipeline: pipeline, context: context, configs: configs, **kwargs, &block)
        builder.build
      end

      def to_messages(dialect: :openai, pipeline:, context: nil, configs: nil, **kwargs, &block)
        builder = new(pipeline: pipeline, context: context, configs: configs, **kwargs, &block)
        builder.to_messages(dialect: dialect)
      end
    end

    private

    def apply_keyword_inputs!(inputs)
      inputs.each do |key, value|
        unless KEYWORD_INPUT_KEYS.include?(key)
          raise ArgumentError, "unknown PromptBuilder input key: #{key.inspect}"
        end

        if key == :authors_note
          raise ArgumentError, "authors_note must be a Hash" unless value.is_a?(Hash)

          authors_note(**value)
          next
        end

        public_send(key, value)
      end
    end

    def merge_configs!(value)
      raise ArgumentError, "configs must be a Hash" unless value.is_a?(Hash)

      current = @input_context || TavernKit::PromptBuilder::Context.new({}, type: :app)
      context_class = current.class
      normalized =
        TavernKit::PromptBuilder::Context.new(
          {},
          module_configs: value,
        ).module_configs

      merged_configs = TavernKit::Utils.deep_merge_hashes(current.module_configs, normalized)

      @input_context =
        context_class.new(
          current.to_h,
          type: current.type || :app,
          id: current.id,
          module_configs: merged_configs,
          strict_keys: current.strict_keys?,
        )
    end

    def coerce_context(value)
      return nil if value.nil?
      return value if value.is_a?(TavernKit::PromptBuilder::Context)
      raise ArgumentError, "context must be a Hash or TavernKit::PromptBuilder::Context" unless value.is_a?(Hash)

      TavernKit::PromptBuilder::Context.build(value, type: :app)
    end
  end
end
