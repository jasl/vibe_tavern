# frozen_string_literal: true

module TavernKit
  module VibeTavern
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
            t = type.to_s.strip
            d = description.to_s.strip
            return "" if t.empty?
            return t if d.empty?

            "#{t} (#{d})"
          end

          private

          def normalize_aliases(value)
            Array(value).map { |a| a.to_s.strip }.reject(&:empty?).uniq
          end
        end

      class Registry
        def initialize(definitions: [])
          @definitions =
            Array(definitions).map do |d|
              case d
              when DirectiveDefinition
                d
              when Hash
                DirectiveDefinition.new(
                  type: d[:type] || d["type"],
                  description: d[:description] || d["description"],
                  aliases: d[:aliases] || d["aliases"],
                )
              else
                raise ArgumentError, "Invalid directive definition: #{d.inspect}"
              end
            end
        end

        def definitions = @definitions

        def types
          definitions.map(&:type).map { |t| t.to_s.strip }.reject(&:empty?).uniq
        end

        def type_aliases
          definitions.each_with_object({}) do |d, out|
            canonical = d.type.to_s.strip
            next if canonical.empty?

            Array(d.aliases).each do |a|
              alias_name = a.to_s.strip
              next if alias_name.empty?

              out[alias_name] ||= canonical
            end
          end
        end

        def instructions_text
          lines = definitions.map(&:instruction_line).map(&:strip).reject(&:empty?)
          return "" if lines.empty?

          [
            "Allowed directive types:",
            *lines.map { |l| "- #{l}" },
          ].join("\n")
        end
      end
    end
  end
end
