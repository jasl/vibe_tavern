# frozen_string_literal: true

require_relative "prompt_builder/context"
require_relative "prompt_builder/state"
require_relative "prompt_builder/step"
require_relative "prompt_builder/pipeline"

module TavernKit
  # PromptBuilder is the only public prompt-construction entrypoint.
  class PromptBuilder
    attr_reader :state
    attr_reader :pipeline
    attr_reader :input_context

    def initialize(pipeline:, context: nil, &block)
      raise ArgumentError, "pipeline: is required" if pipeline.nil?
      raise ArgumentError, "pipeline must be a TavernKit::PromptBuilder::Pipeline" unless pipeline.is_a?(Pipeline)

      @pipeline = pipeline
      @input_context = coerce_context(context)
      context_attrs = @input_context ? @input_context.to_h : {}
      @state = State.new(**context_attrs, context: @input_context)
      @built = false

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

    # Alias to keep builder ergonomics where callers previously supplied runtime.
    def runtime(value)
      @state.runtime = value

      if value.is_a?(TavernKit::PromptBuilder::Context)
        @input_context = value
        @state.context ||= value
      elsif value.is_a?(Hash)
        normalized = TavernKit::PromptBuilder::Context.build(value, type: :app)
        @input_context = normalized
        @state.context ||= normalized
      end

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
      def build(pipeline:, context: nil, **kwargs, &block)
        if block
          builder = new(pipeline: pipeline, context: context, &block)
          builder.build
        else
          builder = new(pipeline: pipeline, context: context)
          kwargs.each do |key, value|
            builder.public_send(key, value) if builder.respond_to?(key)
          end
          builder.build
        end
      end

      def to_messages(dialect: :openai, pipeline:, context: nil, **kwargs, &block)
        builder = new(pipeline: pipeline, context: context)
        builder.dialect(dialect)

        if block
          builder.instance_eval(&block)
        else
          kwargs.each do |key, value|
            builder.public_send(key, value) if builder.respond_to?(key)
          end
        end

        builder.to_messages(dialect: dialect)
      end
    end

    private

    def coerce_context(value)
      return nil if value.nil?
      return value if value.is_a?(TavernKit::PromptBuilder::Context)
      raise ArgumentError, "context must be a Hash or TavernKit::PromptBuilder::Context" unless value.is_a?(Hash)

      TavernKit::PromptBuilder::Context.build(value, type: :app)
    end
  end
end
