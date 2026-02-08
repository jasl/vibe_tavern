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
    # - an object/class that responds to `json_schema`.
    module JsonSchema
      module_function

      def coerce(value)
        return value if value.is_a?(Hash)

        if value.respond_to?(:json_schema)
          schema = value.json_schema
          return schema if schema.is_a?(Hash)

          raise ArgumentError, "json_schema must return a Hash (got #{schema.class})"
        end

        raise ArgumentError, "Unsupported schema provider: #{value.inspect}"
      end
    end
  end
end
