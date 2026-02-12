# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Tools
      module Skills
        SkillMetadata =
          Data.define(
            :name,
            :description,
            :location,
            :license,
            :compatibility,
            :metadata,
            :allowed_tools,
          ) do
            def initialize(
              name:,
              description:,
              location:,
              license: nil,
              compatibility: nil,
              metadata: nil,
              allowed_tools: nil
            )
              name = name.to_s
              description = description.to_s
              location = location.to_s

              super(
                name: name,
                description: description,
                location: location,
                license: blank?(license) ? nil : license.to_s,
                compatibility: blank?(compatibility) ? nil : compatibility.to_s,
                metadata: normalize_metadata(metadata),
                allowed_tools: normalize_allowed_tools(allowed_tools),
              )
            end

            private

            def normalize_metadata(value)
              hash = value.is_a?(Hash) ? value : {}
              hash.each_with_object({}) do |(k, v), out|
                key = k.to_s
                next if key.strip.empty?

                out[key] = v
              end
            end

            def normalize_allowed_tools(value)
              Array(value)
                .map { |v| v.to_s.strip }
                .reject(&:empty?)
                .uniq
            end

            def blank?(value)
              value.nil? || value.to_s.strip.empty?
            end
          end
      end
    end
  end
end
