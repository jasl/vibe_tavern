# frozen_string_literal: true

module AgentCore
  module Contrib
    module Directives
      module Schema
        NAME = "tavern_directives"

        module_function

        def response_format(strict: true, name: NAME, types: nil)
          {
            type: "json_schema",
            json_schema: {
              name: name.to_s,
              strict: strict == true,
              schema: schema_hash(types: types),
            },
          }
        end

        def schema_hash(types: nil)
          type_property = { type: "string" }
          enum = normalize_type_enum(types)
          type_property[:enum] = enum if enum

          {
            type: "object",
            additionalProperties: false,
            required: ["assistant_text", "directives"],
            properties: {
              assistant_text: { type: "string" },
              directives: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: ["type", "payload"],
                  properties: {
                    type: type_property,
                    payload: {
                      type: "object",
                      additionalProperties: true,
                    },
                  },
                },
              },
            },
          }
        end

        def normalize_type_enum(types)
          list = Array(types).map { |t| t.to_s.strip }.reject(&:empty?).uniq
          list.empty? ? nil : list
        end
        private_class_method :normalize_type_enum
      end
    end
  end
end
