# frozen_string_literal: true

require_relative "../json_schema"

module TavernKit
  module VibeTavern
    module ToolsBuilder
      Definition =
        Data.define(:name, :description, :parameters, :exposed_to_model) do
          def initialize(name:, description:, parameters:, exposed_to_model: true)
            parameters_hash =
              if parameters.nil? || parameters.is_a?(Hash)
                parameters
              else
                TavernKit::VibeTavern::JsonSchema.coerce(parameters)
              end

            super(
              name: name.to_s,
              description: description.to_s,
              parameters: parameters_hash.is_a?(Hash) ? parameters_hash : {},
              exposed_to_model: exposed_to_model == true,
            )
          end

          def to_openai_tool
            {
              type: "function",
              function: {
                name: name,
                description: description,
                parameters: normalize_schema(parameters),
              },
            }
          end

          def exposed_to_model? = exposed_to_model == true

          private

          # Providers can be surprisingly strict about JSON schema.
          #
          # Example: some OpenAI-compatible backends reject `required: []`.
          # Omitting the key is equivalent and more compatible.
          def normalize_schema(value)
            case value
            when Hash
              value.each_with_object({}) do |(k, v), out|
                next if k.to_s == "required" && v.is_a?(Array) && v.empty?

                out[k] = normalize_schema(v)
              end
            when Array
              value.map { |v| normalize_schema(v) }
            else
              value
            end
          end
        end
    end
  end
end
