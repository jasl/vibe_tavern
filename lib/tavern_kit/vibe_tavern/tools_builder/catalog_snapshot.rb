# frozen_string_literal: true

require "json"

require_relative "catalog"

module TavernKit
  module VibeTavern
    module ToolsBuilder
      # Precomputed, deterministic snapshot of the model-visible tool surface.
      #
      # This freezes the exposed `tools:` request payload for the lifetime of a
      # ToolLoopRunner instance, improving determinism and avoiding repeated
      # schema materialization.
      class CatalogSnapshot < Catalog
        def self.build_from(base_catalog:, max_count:, max_bytes:)
          raise ArgumentError, "base_catalog is required" if base_catalog.nil?

          max_count = Integer(max_count)
          raise ArgumentError, "max_count must be positive" if max_count <= 0

          max_bytes = Integer(max_bytes)
          raise ArgumentError, "max_bytes must be positive" if max_bytes <= 0

          defs = Array(base_catalog.definitions)
          visible_defs = defs.select { |d| d.respond_to?(:exposed_to_model?) && d.exposed_to_model? }

          if visible_defs.size > max_count
            first_names = visible_defs.first(10).map { |d| d.respond_to?(:name) ? d.name.to_s : "" }.reject(&:empty?)
            raise(
              ArgumentError,
              "tool definitions exceed max_tool_definitions_count=#{max_count} (count=#{visible_defs.size}, first=#{first_names.join(", ")})",
            )
          end

          tools = visible_defs.map(&:to_openai_tool)
          bytes = JSON.generate(tools).bytesize

          if bytes > max_bytes
            debug = biggest_tools_debug(tools)
            msg = "tool definitions exceed max_tool_definitions_bytes=#{max_bytes} (bytes=#{bytes})"
            msg = "#{msg}; biggest=#{debug}" unless debug.empty?
            raise ArgumentError, msg
          end

          new(definitions: visible_defs, openai_tools_model: tools)
        end

        def initialize(definitions:, openai_tools_model:)
          @definitions = Array(definitions)
          @openai_tools_model = Array(openai_tools_model)

          @model_tool_names =
            @definitions.each_with_object({}) do |d, out|
              name = d.respond_to?(:name) ? d.name.to_s : ""
              next if name.strip.empty?

              out[name] = true
            end
        end

        def definitions = @definitions

        def openai_tools(expose: :model)
          return @openai_tools_model if expose == :model

          @definitions.map(&:to_openai_tool)
        end

        def include?(name, expose: :model)
          tool_name = name.to_s
          return false if tool_name.strip.empty?

          if expose == :model
            @model_tool_names.key?(tool_name)
          else
            @definitions.any? { |d| d.respond_to?(:name) && d.name.to_s == tool_name }
          end
        end

        class << self
          private

          def biggest_tools_debug(tools)
            sizes =
              Array(tools).filter_map do |tool|
                next unless tool.is_a?(Hash)

                name = tool.dig(:function, :name) || tool.dig("function", "name")
                name = name.to_s
                next if name.strip.empty?

                bytes =
                  begin
                    JSON.generate(tool).bytesize
                  rescue StandardError
                    tool.to_s.bytesize
                  end

                { name: name, bytes: bytes }
              end

            top =
              sizes
                .sort_by { |h| [-h.fetch(:bytes), h.fetch(:name)] }
                .first(5)

            top.map { |h| "#{h.fetch(:name)}:#{h.fetch(:bytes)}" }.join(", ")
          rescue StandardError
            ""
          end
        end
      end
    end
  end
end
