# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      # Wraps a ToolRegistry and filters the exposed tool surface.
      #
      # This is the core primitive behind "tool profiles" / "tool masking":
      # the model only sees a subset of tools, and the dispatcher enforces the
      # same subset when executing tool calls.
      class FilteredToolRegistry
        def initialize(base:, allow: nil, deny: nil)
          @base = base
          @allow = normalize_names(allow)
          @deny = normalize_names(deny)
        end

        def definitions
          defs = @base.definitions

          if @allow
            allow = @allow
            defs = defs.select { |d| allow.include?(d.name) }
          end

          if @deny
            deny = @deny
            defs = defs.reject { |d| deny.include?(d.name) }
          end

          defs
        end

        def openai_tools(expose: :model)
          defs = definitions
          defs = defs.select(&:exposed_to_model?) if expose == :model
          defs.map(&:to_openai_tool)
        end

        def include?(name, expose: :model)
          defs = definitions
          defs = defs.select(&:exposed_to_model?) if expose == :model
          defs.any? { |d| d.name == name.to_s }
        end

        private

        def normalize_names(value)
          case value
          when nil
            nil
          when String
            names = value.split(",").map(&:strip).reject(&:empty?)
            names.empty? ? nil : names
          when Array
            names = value.map { |v| v.to_s.strip }.reject(&:empty?)
            names.empty? ? nil : names
          else
            names = [value.to_s.strip].reject(&:empty?)
            names.empty? ? nil : names
          end
        end
      end
    end
  end
end
