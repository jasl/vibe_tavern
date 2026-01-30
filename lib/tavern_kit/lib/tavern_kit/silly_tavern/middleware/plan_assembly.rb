# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: build the final Prompt::Plan.
      class PlanAssembly < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.plan = TavernKit::Prompt::Plan.new(
            blocks: ctx.blocks,
            outlets: ctx.outlets,
            lore_result: ctx.lore_result,
            trim_report: ctx.trim_report,
            greeting: ctx.resolved_greeting,
            greeting_index: ctx.resolved_greeting_index,
            warnings: ctx.warnings,
            trace: nil,
          )
        end
      end
    end
  end
end
