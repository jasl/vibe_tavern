# frozen_string_literal: true

module AgentCore
  module Resources
    module Skills
      # Immutable metadata about a skill (name, description, location, etc.)
      #
      # Used for progressive disclosure: list_skills returns metadata only,
      # avoiding the cost of reading full skill bodies.
      SkillMetadata =
        Data.define(
          :name,
          :description,
          :location,
          :license,
          :compatibility,
          :metadata,
          :allowed_tools,
          :allowed_tools_raw,
        ) do
          def initialize(
            name:,
            description:,
            location:,
            license: nil,
            compatibility: nil,
            metadata: nil,
            allowed_tools: nil,
            allowed_tools_raw: nil
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
              allowed_tools_raw: normalize_allowed_tools_raw(allowed_tools_raw, allowed_tools: allowed_tools),
            )
          end

          private

          def normalize_metadata(value)
            hash = value.is_a?(Hash) ? value : {}
            hash.each_with_object({}) do |(k, v), out|
              key = k.to_s
              next if key.strip.empty?

              out[key] = v.to_s
            end
          end

          def normalize_allowed_tools(value)
            list =
              case value
              when String
                value.split(/\s+/)
              else
                Array(value)
              end

            seen = {}
            list.each_with_object([]) do |v, out|
              tool = v.to_s.strip
              next if tool.empty?
              next if seen.key?(tool)

              seen[tool] = true
              out << tool
            end
          end

          def normalize_allowed_tools_raw(value, allowed_tools:)
            raw =
              if !blank?(value)
                value.to_s
              elsif allowed_tools.is_a?(String)
                allowed_tools
              end

            raw = raw.to_s.strip
            raw.empty? ? nil : raw
          end

          def blank?(value)
            value.nil? || value.to_s.strip.empty?
          end
        end
    end
  end
end
