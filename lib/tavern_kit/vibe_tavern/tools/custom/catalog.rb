# frozen_string_literal: true

require_relative "../../tools_builder/catalog"
require_relative "../../tools_builder/definition"

module TavernKit
  module VibeTavern
    module Tools
      module Custom
        # App-owned list of tools and their JSON schema.
        #
        # This catalog is intentionally "dumb": the app owns which tools exist
        # and what they do; ToolCalling only needs to (a) expose the JSON schema
        # to the model and (b) enforce allow/deny rules consistently.
        class Catalog < TavernKit::VibeTavern::ToolsBuilder::Catalog
          def initialize(definitions: [])
            @definitions =
              Array(definitions).map do |d|
                case d
                when TavernKit::VibeTavern::ToolsBuilder::Definition
                  d
                when Hash
                  name = d.fetch(:name)
                  description = d.fetch(:description)
                  parameters = d.fetch(:parameters)

                  exposed =
                    if d.key?(:exposed_to_model)
                      TavernKit::Coerce.bool(d.fetch(:exposed_to_model), default: false)
                    else
                      true
                    end

                  TavernKit::VibeTavern::ToolsBuilder::Definition.new(
                    name: name,
                    description: description,
                    parameters: parameters,
                    exposed_to_model: exposed,
                  )
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
            tool_name = name.to_s
            defs = definitions
            defs = defs.select(&:exposed_to_model?) if expose == :model
            defs.any? { |d| d.name == tool_name }
          end
        end
      end
    end
  end
end
