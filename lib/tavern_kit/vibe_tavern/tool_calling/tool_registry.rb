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
                parameters: parameters,
              },
            }
          end

          def exposed_to_model? = exposed_to_model == true
        end

      # PoC registry: a small allowlist of tools used to validate tool-calling loops.
      #
      # The "real" editor will likely maintain a larger registry, potentially
      # with per-user authorization and side-effect levels.
      class ToolRegistry
        def definitions
          [
            ToolDefinition.new(
              name: "state.get",
              description: "Read workspace state (facts/draft/locks/ui_state/versions).",
              parameters: {
                type: "object",
                additionalProperties: false,
                properties: {
                  workspace_id: { type: "string" },
                  select: { type: "array", items: { type: "string" } },
                },
                required: ["workspace_id"],
              },
            ),
            ToolDefinition.new(
              name: "state.patch",
              description: "Apply patch operations to draft state (set/delete/append/insert).",
              parameters: {
                type: "object",
                additionalProperties: false,
                properties: {
                  workspace_id: { type: "string" },
                  request_id: { type: "string" },
                  draft_etag: { type: "string" },
                  ops: {
                    type: "array",
                    items: {
                      type: "object",
                      additionalProperties: false,
                      properties: {
                        op: { type: "string" },
                        path: { type: "string" },
                        value: {},
                        index: { type: "integer" },
                      },
                      required: ["op", "path"],
                    },
                  },
                },
                required: ["workspace_id", "request_id", "ops"],
              },
            ),
            ToolDefinition.new(
              name: "facts.propose",
              description: "Propose facts changes (requires explicit user confirmation to commit).",
              parameters: {
                type: "object",
                additionalProperties: false,
                properties: {
                  workspace_id: { type: "string" },
                  request_id: { type: "string" },
                  proposals: {
                    type: "array",
                    items: {
                      type: "object",
                      additionalProperties: false,
                      properties: {
                        path: { type: "string" },
                        value: {},
                        reason: { type: "string" },
                      },
                      required: ["path", "value"],
                    },
                  },
                },
                required: ["workspace_id", "request_id", "proposals"],
              },
            ),
            ToolDefinition.new(
              name: "facts.commit",
              description: "Commit a facts proposal (must be triggered by UI/user confirmation).",
              exposed_to_model: false,
              parameters: {
                type: "object",
                additionalProperties: false,
                properties: {
                  workspace_id: { type: "string" },
                  request_id: { type: "string" },
                  proposal_id: { type: "string" },
                  user_confirmed: { type: "boolean" },
                },
                required: ["workspace_id", "request_id", "proposal_id", "user_confirmed"],
              },
            ),
            ToolDefinition.new(
              name: "ui.render",
              description: "Request UI actions (panel/form/modal/upload/etc). No business side effects.",
              parameters: {
                type: "object",
                additionalProperties: false,
                properties: {
                  workspace_id: { type: "string" },
                  request_id: { type: "string" },
                  actions: { type: "array", items: { type: "object" } },
                },
                required: ["workspace_id", "request_id", "actions"],
              },
            ),
          ]
        end

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
