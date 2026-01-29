# frozen_string_literal: true

module TavernKit
  module Prompt
    # DSL for building prompts in a Ruby-idiomatic style.
    #
    # Requires an explicit pipeline: parameter — there is no default pipeline.
    #
    # @example Block-based DSL
    #   plan = TavernKit::Prompt::DSL.build(pipeline: my_pipeline) do
    #     character my_char
    #     user my_user
    #     preset my_preset
    #     message "Hello!"
    #   end
    #
    # @example Fluent API
    #   dsl = TavernKit::Prompt::DSL.new(pipeline: my_pipeline)
    #   dsl.character(my_char)
    #   dsl.user(my_user)
    #   dsl.message("Hello!")
    #   plan = dsl.build
    #
    class DSL
      # @return [Context] the prompt context being built
      attr_reader :context

      # @return [Pipeline] the pipeline to use
      attr_reader :pipeline

      # @param pipeline [Pipeline] the pipeline to use (required)
      def initialize(pipeline:, &block)
        raise ArgumentError, "pipeline: is required" if pipeline.nil?

        @context = Context.new
        @pipeline = pipeline
        @built = false

        instance_eval(&block) if block
      end

      # Set the character.
      def character(value)
        @context.character = value
        self
      end

      # Set the user/persona.
      def user(value)
        @context.user = value
        self
      end

      # Set the preset configuration.
      def preset(value)
        @context.preset = value
        self
      end

      # Set the chat history.
      def history(value)
        @context.history = value
        self
      end

      # Set the user message.
      def message(text)
        @context.user_message = text.to_s
        self
      end

      # Add a lore book.
      def lore_book(book)
        @context.lore_books << book
        self
      end

      # Add multiple lore books.
      def lore_books(books)
        @context.lore_books.concat(Array(books))
        self
      end

      # Set the generation type.
      def generation_type(type)
        @context.generation_type = type
        self
      end

      # Set the group context.
      def group(value)
        @context.group = value
        self
      end

      # Set greeting index.
      def greeting(index)
        @context.greeting_index = index
        self
      end

      # Set Author's Note overrides.
      def authors_note(position: nil, depth: nil, role: nil)
        overrides = {}
        overrides[:position] = position if position
        overrides[:depth] = depth if depth
        overrides[:role] = role if role
        @context.authors_note_overrides = overrides.empty? ? nil : overrides
        self
      end

      # Set macro variables.
      def macro_vars(vars)
        @context.macro_vars = vars&.transform_keys { |k| k.to_s.downcase.to_sym }
        self
      end

      # Set or add a macro variable.
      def set_var(key, value)
        @context.macro_vars ||= {}
        @context.macro_vars[key.to_s.downcase.to_sym] = value
        self
      end

      # Set the macro registry.
      def macro_registry(registry)
        @context.macro_registry = registry
        self
      end

      # Set the injection registry.
      def injection_registry(registry)
        @context.injection_registry = registry
        self
      end

      # Set the hook registry.
      def hook_registry(registry)
        @context.hook_registry = registry
        self
      end

      # Force activate World Info entries.
      def force_world_info(activations)
        @context.forced_world_info_activations = Array(activations)
        self
      end

      # Set the token estimator.
      def token_estimator(estimator)
        @context.token_estimator = estimator
        self
      end

      # Set the lore engine.
      def lore_engine(engine)
        @context.lore_engine = engine
        self
      end

      # Set the macro expander.
      def expander(expander)
        @context.expander = expander
        self
      end

      # Set the warning handler.
      def warning_handler(handler)
        @context.warning_handler = handler
        self
      end

      # Set the debug instrumenter (typically nil in production).
      def instrumenter(instrumenter)
        @context.instrumenter = instrumenter
        self
      end

      # Enable or disable strict mode.
      def strict(enabled = true)
        @context.strict = enabled
        self
      end

      # Configure a specific middleware.
      def configure_middleware(name, **options)
        @pipeline = @pipeline.dup
        @pipeline.configure(name, **options)
        self
      end

      # Replace a middleware.
      def replace_middleware(name, middleware, **options)
        @pipeline = @pipeline.dup
        @pipeline.replace(name, middleware, **options)
        self
      end

      # Insert a middleware before another.
      def insert_middleware_before(before_name, middleware, name: nil, **options)
        @pipeline = @pipeline.dup
        @pipeline.insert_before(before_name, middleware, name: name, **options)
        self
      end

      # Insert a middleware after another.
      def insert_middleware_after(after_name, middleware, name: nil, **options)
        @pipeline = @pipeline.dup
        @pipeline.insert_after(after_name, middleware, name: name, **options)
        self
      end

      # Remove a middleware.
      def remove_middleware(name)
        @pipeline = @pipeline.dup
        @pipeline.remove(name)
        self
      end

      # Build the prompt plan.
      # @return [Plan]
      def build
        raise "DSL has already been built" if @built

        @built = true
        @context.macro_vars ||= {}

        @pipeline.call(@context)
        @context.plan
      end

      # Build and convert to messages.
      def to_messages(dialect: :openai)
        plan = build
        plan.to_messages(dialect: dialect)
      end

      # Class methods for convenient access
      class << self
        def build(pipeline:, &block)
          dsl = new(pipeline: pipeline, &block)
          dsl.build
        end

        def to_messages(dialect: :openai, pipeline:, &block)
          dsl = new(pipeline: pipeline, &block)
          dsl.to_messages(dialect: dialect)
        end
      end
    end
  end
end
