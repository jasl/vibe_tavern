# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      class ToolDispatcher
        TOOL_NAME_ALIASES = {
          "state.get" => "state_get",
          "state.patch" => "state_patch",
          "facts.propose" => "facts_propose",
          "facts.commit" => "facts_commit",
          "ui.render" => "ui_render",
        }.freeze

        def initialize(workspace:, registry: nil, expose: :model)
          @workspace = workspace
          @registry = registry || ToolRegistry.new
          @expose = expose
        end

        def execute(name:, args:)
          name = TOOL_NAME_ALIASES.fetch(name.to_s, name.to_s)
          args = args.is_a?(Hash) ? args : {}

          unless @registry.include?(name, expose: @expose)
            return error_envelope(name, code: "TOOL_NOT_ALLOWED", message: "Tool not allowed: #{name}")
          end

          workspace_id = args["workspace_id"].to_s
          if workspace_id.empty? || workspace_id != @workspace.id
            return error_envelope(name, code: "WORKSPACE_NOT_FOUND", message: "Unknown workspace_id: #{workspace_id}")
          end

          case name
          when "state_get"
            ok_envelope(name, "snapshot" => @workspace.snapshot(select: args["select"]))
          when "state_patch"
            result = @workspace.patch_draft!(args["ops"], etag: args["draft_etag"])
            ok_envelope(name, result)
          when "facts_propose"
            proposal_id = @workspace.propose_facts!(args["proposals"])
            ok_envelope(name, "proposal_id" => proposal_id)
          when "facts_commit"
            result = @workspace.commit_facts!(args["proposal_id"], user_confirmed: args["user_confirmed"])
            ok_envelope(name, result)
          when "ui_render"
            actions = Array(args["actions"])
            # Store last UI render request for debugging / testing.
            @workspace.ui_state["last_render"] = { "actions" => actions }
            ok_envelope(name, "rendered" => actions.size)
          else
            error_envelope(name, code: "TOOL_NOT_IMPLEMENTED", message: "Tool not implemented: #{name}")
          end
        rescue ArgumentError => e
          error_envelope(name, code: "ARGUMENT_ERROR", message: e.message)
        rescue StandardError => e
          # Unexpected programming error: surface clearly so tests/debugging can catch it.
          error_envelope(name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
        end

        private

        def ok_envelope(name, data)
          {
            "ok" => true,
            "tool_name" => name,
            "data" => data.is_a?(Hash) ? data : { "value" => data },
            "warnings" => [],
            "errors" => [],
          }
        end

        def error_envelope(name, code:, message:)
          {
            "ok" => false,
            "tool_name" => name,
            "data" => {},
            "warnings" => [],
            "errors" => [
              {
                "code" => code,
                "message" => message.to_s,
              },
            ],
          }
        end
      end
    end
  end
end
