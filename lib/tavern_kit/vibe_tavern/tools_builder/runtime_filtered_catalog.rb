# frozen_string_literal: true

require_relative "catalog"

module TavernKit
  module VibeTavern
    module ToolsBuilder
      # Wraps a catalog and applies a runtime allow-set for model exposure and execution enforcement.
      #
      # This enables ToolLoopRunner to tighten the tool surface dynamically after a successful
      # skills_load (allowed-tools), while keeping a single source of truth for both:
      # - what is sent in the LLM request (`tools:`)
      # - what ToolDispatcher will execute (`include?`)
      class RuntimeFilteredCatalog < Catalog
        def initialize(base:, allow_set_fn:)
          raise ArgumentError, "base is required" if base.nil?
          unless base.is_a?(TavernKit::VibeTavern::ToolsBuilder::Catalog)
            raise ArgumentError, "base must be a ToolsBuilder::Catalog (got #{base.class})"
          end
          raise ArgumentError, "allow_set_fn is required" unless allow_set_fn.respond_to?(:call)

          @base = base
          @allow_set_fn = allow_set_fn
        end

        def definitions
          defs = @base.definitions
          allow = allow_set
          return defs if allow.nil?

          Array(defs).select do |d|
            name = d.respond_to?(:name) ? d.name.to_s : ""
            allow.key?(name)
          end
        end

        def openai_tools(expose: :model)
          tools = @base.openai_tools(expose: expose)
          return tools unless expose == :model

          allow = allow_set
          return tools if allow.nil?

          Array(tools).select do |tool|
            name = extract_openai_tool_name(tool)
            allow.key?(name)
          end
        end

        def include?(name, expose: :model)
          return @base.include?(name, expose: expose) unless expose == :model

          allow = allow_set
          return @base.include?(name, expose: expose) if allow.nil?

          tool_name = name.to_s
          return false if tool_name.strip.empty?
          return false unless @base.include?(tool_name, expose: expose)

          allow.key?(tool_name)
        end

        private

        def allow_set
          set = @allow_set_fn.call
          return nil if set.nil?
          return set if set.is_a?(Hash)

          nil
        rescue StandardError
          nil
        end

        def extract_openai_tool_name(tool)
          return "" unless tool.is_a?(Hash)

          fn = tool.fetch(:function, nil)
          fn = tool.fetch("function", nil) unless fn.is_a?(Hash)
          return "" unless fn.is_a?(Hash)

          name = fn.fetch(:name, fn.fetch("name", nil)).to_s
          name.strip
        rescue StandardError
          ""
        end
      end
    end
  end
end
