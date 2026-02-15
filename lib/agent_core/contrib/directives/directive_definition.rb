# frozen_string_literal: true

module AgentCore
  module Contrib
    module Directives
      DirectiveDefinition =
        Data.define(:type, :description, :aliases) do
          def initialize(type:, description:, aliases: nil)
            super(
              type: type.to_s,
              description: description.to_s,
              aliases: normalize_aliases(aliases),
            )
          end

          def instruction_line
            type_str = type.to_s.strip
            description_str = description.to_s.strip
            return "" if type_str.empty?
            return type_str if description_str.empty?

            "#{type_str} (#{description_str})"
          end

          private

          def normalize_aliases(value)
            Array(value).map { |a| a.to_s.strip }.reject(&:empty?).uniq
          end
        end
    end
  end
end
