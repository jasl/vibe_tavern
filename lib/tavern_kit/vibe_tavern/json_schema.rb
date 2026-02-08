# frozen_string_literal: true

module TavernKit
  module VibeTavern
    # Helper utilities for working with JSON Schema providers.
    #
    # Motivation:
    # - The infra accepts schema Hashes (tool parameters, structured outputs).
    # - App code often prefers a higher-level schema DSL (e.g. EasyTalk).
    #
    # This module allows passing either:
    # - a plain Hash, or
    # - an object/class that responds to `json_schema`, or
    # - an object/class that responds to `to_json_schema` (RubyLLM-style metadata Hash).
    module JsonSchema
      module_function

      def coerce(value)
        return value if value.is_a?(Hash)

        if value.respond_to?(:json_schema)
          schema = value.json_schema
          return schema if schema.is_a?(Hash)

          raise ArgumentError, "json_schema must return a Hash (got #{schema.class})"
        end

        if value.respond_to?(:to_json_schema)
          meta = value.to_json_schema
          meta = meta.is_a?(Hash) ? meta : {}
          schema = meta[:schema] || meta["schema"]
          return schema if schema.is_a?(Hash)

          raise ArgumentError, "to_json_schema must return a Hash with :schema (got #{meta.inspect})"
        end

        raise ArgumentError, "Unsupported schema provider: #{value.inspect}"
      end
    end
  end
end
