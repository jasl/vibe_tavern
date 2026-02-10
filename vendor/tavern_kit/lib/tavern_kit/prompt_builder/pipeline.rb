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

      # Entry representing a step in the pipeline.
      Entry = Data.define(:step_class, :options, :name, :config_class, :default_config)

      Frame = Data.define(:name, :step_class, :config, :prev_step)

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

        initial_step = state.current_step
        frames = []
        idx = 0

        pipeline_error = nil
        pipeline_error_cause = nil

        while idx < @entries.size && pipeline_error.nil?
          entry = @entries[idx]
          config = resolve_step_config(entry, state)
          prev_step = state.current_step
          state.current_step = entry.name
          frames << Frame.new(
            name: entry.name,
            step_class: entry.step_class,
            config: config,
            prev_step: prev_step,
          )

          state.instrument(:step_start, name: entry.name)

          begin
            entry.step_class.before(state, config)
            idx += 1
          rescue StandardError => e
            state.instrument(:step_error, name: entry.name, error: e)
            frames.pop
            state.current_step = prev_step

            pipeline_error, pipeline_error_cause = coerce_pipeline_error(e, step: entry.name)
          end
        end

        if pipeline_error.nil?
          while frames.any?
            frame = frames.pop
            state.current_step = frame.name

            begin
              frame.step_class.after(state, frame.config)
              state.instrument(:step_finish, name: frame.name)
              state.current_step = frame.prev_step
            rescue StandardError => e
              state.instrument(:step_error, name: frame.name, error: e)
              state.current_step = frame.prev_step

              pipeline_error, pipeline_error_cause = coerce_pipeline_error(e, step: frame.name)
              break
            end
          end
        end

        if pipeline_error
          while frames.any?
            frame = frames.pop
            state.current_step = frame.name
            state.instrument(:step_error, name: frame.name, error: pipeline_error)
            state.current_step = frame.prev_step
          end

          state.current_step = initial_step
          raise_with_cause(pipeline_error, pipeline_error_cause)
        end

        state.current_step = initial_step
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

      def resolve_step_config(entry, state)
        context = state.context
        overrides = context&.module_configs&.fetch(entry.name, nil)

        has_overrides = overrides.is_a?(Hash) && overrides.any?

        if has_overrides
          merged = TavernKit::Utils.deep_merge_hashes(entry.options, overrides)
          resolve_typed_config(entry.name, entry.config_class, merged)
        else
          entry.default_config
        end
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
        unless step_class.const_defined?(:Config, false)
          raise ArgumentError, "#{step_class} must define a Config class"
        end

        config_class = step_class.const_get(:Config, false)
        unless config_class.respond_to?(:from_hash)
          raise ArgumentError, "#{step_class}::Config must respond to .from_hash"
        end

        config_class
      end

      def resolve_default_config(name, config_class, options)
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

      def coerce_pipeline_error(error, step:)
        return [error, nil] if error.is_a?(TavernKit::PipelineError)

        [
          TavernKit::PipelineError.new("#{error.class}: #{error.message}", step: step),
          error,
        ]
      end

      def raise_with_cause(error, cause)
        if cause
          raise error, cause: cause
        end

        raise error
      end
    end
  end
end
