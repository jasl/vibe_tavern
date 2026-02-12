# frozen_string_literal: true

require_relative "../../tools_builder/definition"

module TavernKit
  module VibeTavern
    module Tools
      module Skills
        module ToolDefinitions
          module_function

          def definitions(include_run_script: false)
            defs = [
              ToolsBuilder::Definition.new(
                name: "skills_list",
                description: "List available agent skills (metadata only).",
                parameters: { type: "object", properties: {} },
              ),
              ToolsBuilder::Definition.new(
                name: "skills_load",
                description: "Load a skill's SKILL.md body (progressive disclosure).",
                parameters: {
                  type: "object",
                  properties: {
                    name: { type: "string", description: "Skill name" },
                  },
                  required: ["name"],
                },
              ),
              ToolsBuilder::Definition.new(
                name: "skills_read_file",
                description: "Read a file bundled with a skill (scripts/, references/, assets/).",
                parameters: {
                  type: "object",
                  properties: {
                    name: { type: "string", description: "Skill name" },
                    path: { type: "string", description: "Relative path like references/foo.md" },
                  },
                  required: ["name", "path"],
                },
              ),
            ]

            if include_run_script
              defs <<
                ToolsBuilder::Definition.new(
                  name: "skills_run_script",
                  description: "Run a skill script (not implemented).",
                  parameters: {
                    type: "object",
                    properties: {
                      name: { type: "string", description: "Skill name" },
                      script: { type: "string", description: "Relative script path under scripts/" },
                      args: { type: "object", description: "Arguments (JSON object)" },
                    },
                    required: ["name", "script"],
                  },
                )
            end

            defs
          end
        end
      end
    end
  end
end
