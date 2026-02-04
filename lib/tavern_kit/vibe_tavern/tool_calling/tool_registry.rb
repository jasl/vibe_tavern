# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      ToolDefinition =
        Data.define(:name, :description, :parameters, :exposed_to_model) do
          def initialize(name:, description:, parameters:, exposed_to_model: true)
            super(
              name: name.to_s,
              description: description.to_s,
              parameters: parameters.is_a?(Hash) ? parameters : {},
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

      # A small registry that holds tool definitions.
      #
      # This is intentionally "dumb": the app (or scripts) owns which tools
      # exist and what they do; ToolCalling only needs to (a) expose the JSON
      # schema to the model and (b) enforce allow/deny rules consistently.
      class ToolRegistry
        # OpenAI/Bedrock/Azure (and others) commonly enforce:
        #   ^[a-zA-Z0-9_-]{1,128}$
        #
        # Avoid "." in tool names for maximum cross-provider compatibility.
        def initialize(definitions: [])
          @definitions =
            Array(definitions).map do |d|
              case d
              when ToolDefinition
                d
              when Hash
                attrs = {
                  name: d[:name] || d["name"],
                  description: d[:description] || d["description"],
                  parameters: d[:parameters] || d["parameters"],
                }

                exposed =
                  if d.key?(:exposed_to_model)
                    d[:exposed_to_model]
                  elsif d.key?("exposed_to_model")
                    d["exposed_to_model"]
                  end
                attrs[:exposed_to_model] = exposed unless exposed.nil?

                ToolDefinition.new(**attrs)
              else
                raise ArgumentError, "Invalid tool definition: #{d.inspect}"
              end
            end
        end

        def definitions = @definitions

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
      end
    end
  end
end
