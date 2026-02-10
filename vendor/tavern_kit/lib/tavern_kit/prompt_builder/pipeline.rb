# frozen_string_literal: true

require_relative "step"

module TavernKit
  class PromptBuilder
    # A composable step pipeline for prompt construction.
    #
    # The Pipeline manages an ordered stack of steps that process
    # a State object. Each step can transform the state before
    # and after passing to subsequent steps.
    #
    # This is the workflow orchestrator. Specific platform workflows
    # configurations (e.g., SillyTavern 9-stage) are defined elsewhere.
    #
    # @example Building a pipeline from scratch
    #   pipeline = Pipeline.new do
    #     use_step MyStep, name: :my_step
    #   end
    #
    class Pipeline
      include Enumerable

      # Terminal handler for the step stack.
      class Terminal
        def call(state)
          state
        end
      end
      TERMINAL = Terminal.new

      # Entry representing a step in the pipeline.
      Entry = Data.define(:step_class, :options, :name)

      # Create an empty pipeline (no steps).
      # @return [Pipeline]
      def self.empty
        new
      end

      def initialize(&block)
        @entries = []
        @index = {}
        instance_eval(&block) if block
      end

      # Deep copy for safe modification.
      def initialize_copy(original)
        super
        @entries = original.instance_variable_get(:@entries).map(&:dup)
        @index = original.instance_variable_get(:@index).dup
      end

      # Add a step to the end of the pipeline.
      def use_step(step_class, name: nil, **options)
        resolved_name = resolve_name(step_class, name)

        if @index.key?(resolved_name)
          raise ArgumentError, "Step name already registered: #{resolved_name}"
        end

        entry = Entry.new(step_class: step_class, options: options, name: resolved_name)
        @entries << entry
        @index[resolved_name] = @entries.size - 1
        self
      end

      # Replace a step by name.
      def replace_step(name, step_class, **options)
        idx = @index[name]
        raise ArgumentError, "Unknown step: #{name}" unless idx

        @entries[idx] = Entry.new(step_class: step_class, options: options, name: name)
        self
      end

      # Insert a step before another.
      def insert_step_before(before_name, step_class, name: nil, **options)
        idx = @index[before_name]
        raise ArgumentError, "Unknown step: #{before_name}" unless idx

        resolved_name = resolve_name(step_class, name)
        if @index.key?(resolved_name)
          raise ArgumentError, "Step name already registered: #{resolved_name}"
        end

        entry = Entry.new(step_class: step_class, options: options, name: resolved_name)
        @entries.insert(idx, entry)
        reindex!
        self
      end

      # Insert a step after another.
      def insert_step_after(after_name, step_class, name: nil, **options)
        idx = @index[after_name]
        raise ArgumentError, "Unknown step: #{after_name}" unless idx

        resolved_name = resolve_name(step_class, name)
        if @index.key?(resolved_name)
          raise ArgumentError, "Step name already registered: #{resolved_name}"
        end

        entry = Entry.new(step_class: step_class, options: options, name: resolved_name)
        @entries.insert(idx + 1, entry)
        reindex!
        self
      end

      # Remove a step by name.
      def remove_step(name)
        idx = @index[name]
        raise ArgumentError, "Unknown step: #{name}" unless idx

        @entries.delete_at(idx)
        reindex!
        self
      end

      # Configure options for a step.
      def configure_step(name, **options)
        idx = @index[name]
        raise ArgumentError, "Unknown step: #{name}" unless idx

        entry = @entries[idx]
        @entries[idx] = Entry.new(
          step_class: entry.step_class,
          options: entry.options.merge(options),
          name: entry.name,
        )
        self
      end

      # Execute the pipeline on a state.
      def call(state)
        state = coerce_state(state)
        stack = build_stack(state)
        stack.call(state)
        state
      end

      def each(&block)
        @entries.each(&block)
      end

      def size = @entries.size
      def empty? = @entries.empty?

      def names
        @entries.map(&:name)
      end

      def has?(name)
        @index.key?(name)
      end

      def [](name)
        idx = @index[name]
        idx ? @entries[idx] : nil
      end

      private

      def resolve_name(step_class, name)
        return name if name

        if step_class.respond_to?(:step_name)
          step_class.step_name
        else
          step_class.name.split("::").last
            .gsub(/Step$/, "")
            .gsub(/([a-z])([A-Z])/, '\1_\2')
            .downcase
            .to_sym
        end
      end

      def reindex!
        @index.clear
        @entries.each_with_index do |entry, idx|
          @index[entry.name] = idx
        end
      end

      def build_stack(state)
        app = TERMINAL

        @entries.reverse_each do |entry|
          step_options = resolve_step_options(entry, state)
          app = entry.step_class.new(app, **step_options, __step: entry.name)
        end

        app
      end

      def resolve_step_options(entry, state)
        base = entry.options
        context = state.context
        return base unless context

        overrides = context.module_configs.fetch(entry.name, nil)
        return base unless overrides.is_a?(Hash) && overrides.any?

        base.merge(overrides)
      end

      def coerce_state(value)
        return value if value.is_a?(TavernKit::PromptBuilder::State)

        if value.is_a?(TavernKit::PromptBuilder::Context)
          attrs = value.to_h
          return TavernKit::PromptBuilder::State.new(**attrs, context: value)
        end

        raise ArgumentError, "state must be a TavernKit::PromptBuilder::State or TavernKit::PromptBuilder::Context"
      end
    end
  end
end
