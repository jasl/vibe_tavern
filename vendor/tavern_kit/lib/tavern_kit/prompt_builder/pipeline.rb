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
    # configurations (e.g., SillyTavern 9-step) are defined elsewhere.
    #
    # @example Building a pipeline from scratch
    #   pipeline = Pipeline.new do
    #     use_step :my_step, MyStep
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
      Entry = Data.define(:step_class, :options, :name, :config_class, :default_config)

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
      def use_step(name, step_class, **options)
        unless name.is_a?(Symbol)
          raise ArgumentError, "step name must be a Symbol (got #{name.class})"
        end

        if @index.key?(name)
          raise ArgumentError, "Step name already registered: #{name}"
        end

        entry =
          build_entry(
            step_class: step_class,
            name: name,
            options: options,
          )
        @entries << entry
        @index[name] = @entries.size - 1
        self
      end

      # Replace a step by name.
      def replace_step(name, step_class, **options)
        idx = @index[name]
        raise ArgumentError, "Unknown step: #{name}" unless idx

        @entries[idx] =
          build_entry(
            step_class: step_class,
            name: name,
            options: options,
          )
        self
      end

      # Insert a step before another.
      def insert_step_before(before_name, name, step_class, **options)
        unless before_name.is_a?(Symbol)
          raise ArgumentError, "before_name must be a Symbol (got #{before_name.class})"
        end

        idx = @index[before_name]
        raise ArgumentError, "Unknown step: #{before_name}" unless idx

        unless name.is_a?(Symbol)
          raise ArgumentError, "step name must be a Symbol (got #{name.class})"
        end

        raise ArgumentError, "Step name already registered: #{name}" if @index.key?(name)

        entry =
          build_entry(
            step_class: step_class,
            name: name,
            options: options,
          )
        @entries.insert(idx, entry)
        reindex!
        self
      end

      # Insert a step after another.
      def insert_step_after(after_name, name, step_class, **options)
        unless after_name.is_a?(Symbol)
          raise ArgumentError, "after_name must be a Symbol (got #{after_name.class})"
        end

        idx = @index[after_name]
        raise ArgumentError, "Unknown step: #{after_name}" unless idx

        unless name.is_a?(Symbol)
          raise ArgumentError, "step name must be a Symbol (got #{name.class})"
        end

        raise ArgumentError, "Step name already registered: #{name}" if @index.key?(name)

        entry =
          build_entry(
            step_class: step_class,
            name: name,
            options: options,
          )
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
        merged_options = TavernKit::Utils.deep_merge_hashes(entry.options, options)

        @entries[idx] = Entry.new(
          step_class: entry.step_class,
          options: merged_options,
          name: entry.name,
          config_class: entry.config_class,
          default_config: resolve_default_config(entry.name, entry.config_class, merged_options),
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
        if entry.config_class
          return resolve_typed_config_options(entry, state, base)
        end

        context = state.context
        return base unless context

        overrides = context.module_configs.fetch(entry.name, nil)
        return base unless overrides.is_a?(Hash) && overrides.any?

        TavernKit::Utils.deep_merge_hashes(base, overrides)
      end

      def resolve_typed_config_options(entry, state, base)
        context = state.context
        overrides = context&.module_configs&.fetch(entry.name, nil)
        has_overrides = overrides.is_a?(Hash) && overrides.any?

        typed =
          if has_overrides
            merged = TavernKit::Utils.deep_merge_hashes(base, overrides)
            resolve_typed_config(entry.name, entry.config_class, merged)
          else
            entry.default_config
          end

        { config: typed }
      end

      def coerce_state(value)
        return value if value.is_a?(TavernKit::PromptBuilder::State)

        if value.is_a?(TavernKit::PromptBuilder::Context)
          attrs = value.to_h
          return TavernKit::PromptBuilder::State.new(**attrs, context: value)
        end

        raise ArgumentError, "state must be a TavernKit::PromptBuilder::State or TavernKit::PromptBuilder::Context"
      end

      def build_entry(step_class:, name:, options:)
        resolved_config_class = resolve_config_class(step_class)
        default_config = resolve_default_config(name, resolved_config_class, options)

        Entry.new(
          step_class: step_class,
          options: options,
          name: name,
          config_class: resolved_config_class,
          default_config: default_config,
        )
      end

      def resolve_config_class(step_class)
        return nil unless step_class.const_defined?(:Config, false)

        config_class = step_class.const_get(:Config, false)
        unless config_class.respond_to?(:from_hash)
          raise ArgumentError, "#{step_class}::Config must respond to .from_hash"
        end

        config_class
      end

      def resolve_default_config(name, config_class, options)
        return nil unless config_class

        resolve_typed_config(name, config_class, options)
      end

      def resolve_typed_config(name, config_class, raw)
        config =
          begin
            raw.is_a?(config_class) ? raw : config_class.from_hash(raw)
          rescue StandardError => e
            raise ArgumentError, "invalid config for step #{name}: #{e.message}"
          end

        if config_class && !config.is_a?(config_class)
          raise ArgumentError, "config for step #{name} must be a #{config_class}"
        end

        config
      end
    end
  end
end
