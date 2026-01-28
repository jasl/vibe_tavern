# frozen_string_literal: true

require_relative "middleware/base"

module TavernKit
  module Prompt
    # A composable middleware pipeline for prompt construction.
    #
    # The Pipeline manages an ordered stack of middlewares that process
    # a Context object. Each middleware can transform the context before
    # and after passing to subsequent middlewares.
    #
    # This is the pipeline-agnostic orchestrator. Specific pipeline
    # configurations (e.g., SillyTavern 9-stage) are defined elsewhere.
    #
    # @example Building a pipeline from scratch
    #   pipeline = Pipeline.new do
    #     use MyMiddleware, name: :my_step
    #   end
    #
    class Pipeline
      include Enumerable

      # Terminal handler for the middleware stack.
      class Terminal
        def call(ctx)
          ctx
        end
      end

      # Entry representing a middleware in the pipeline.
      Entry = Data.define(:middleware, :options, :name)

      # Create an empty pipeline (no middlewares).
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

      # Add a middleware to the end of the pipeline.
      def use(middleware, name: nil, **options)
        resolved_name = resolve_name(middleware, name)

        if @index.key?(resolved_name)
          raise ArgumentError, "Middleware name already registered: #{resolved_name}"
        end

        entry = Entry.new(middleware: middleware, options: options, name: resolved_name)
        @entries << entry
        @index[resolved_name] = @entries.size - 1
        self
      end

      # Replace a middleware by name.
      def replace(name, middleware, **options)
        idx = @index[name]
        raise ArgumentError, "Unknown middleware: #{name}" unless idx

        @entries[idx] = Entry.new(middleware: middleware, options: options, name: name)
        self
      end

      # Insert a middleware before another.
      def insert_before(before_name, middleware, name: nil, **options)
        idx = @index[before_name]
        raise ArgumentError, "Unknown middleware: #{before_name}" unless idx

        resolved_name = resolve_name(middleware, name)
        if @index.key?(resolved_name)
          raise ArgumentError, "Middleware name already registered: #{resolved_name}"
        end

        entry = Entry.new(middleware: middleware, options: options, name: resolved_name)
        @entries.insert(idx, entry)
        reindex!
        self
      end

      # Insert a middleware after another.
      def insert_after(after_name, middleware, name: nil, **options)
        idx = @index[after_name]
        raise ArgumentError, "Unknown middleware: #{after_name}" unless idx

        resolved_name = resolve_name(middleware, name)
        if @index.key?(resolved_name)
          raise ArgumentError, "Middleware name already registered: #{resolved_name}"
        end

        entry = Entry.new(middleware: middleware, options: options, name: resolved_name)
        @entries.insert(idx + 1, entry)
        reindex!
        self
      end

      # Remove a middleware by name.
      def remove(name)
        idx = @index[name]
        raise ArgumentError, "Unknown middleware: #{name}" unless idx

        @entries.delete_at(idx)
        reindex!
        self
      end

      # Configure options for a middleware.
      def configure(name, **options)
        idx = @index[name]
        raise ArgumentError, "Unknown middleware: #{name}" unless idx

        entry = @entries[idx]
        @entries[idx] = Entry.new(
          middleware: entry.middleware,
          options: entry.options.merge(options),
          name: entry.name,
        )
        self
      end

      # Execute the pipeline on a context.
      def call(ctx)
        stack = build_stack
        stack.call(ctx)
        ctx
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

      def resolve_name(middleware, name)
        return name if name

        if middleware.respond_to?(:middleware_name)
          middleware.middleware_name
        else
          middleware.name.split("::").last
            .gsub(/Middleware$/, "")
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

      def build_stack
        app = Terminal.new

        @entries.reverse_each do |entry|
          app = entry.middleware.new(app, **entry.options)
        end

        app
      end
    end
  end
end
