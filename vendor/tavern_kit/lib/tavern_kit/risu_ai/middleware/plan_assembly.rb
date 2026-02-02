# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Final stage: build a Prompt::Plan from accumulated blocks.
      class PlanAssembly < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.blocks ||= []

          ctx.plan = TavernKit::Prompt::Plan.new(
            blocks: ctx.blocks,
            outlets: ctx.outlets,
            lore_result: ctx.lore_result,
            trim_report: ctx.trim_report,
            greeting: ctx.resolved_greeting,
            greeting_index: ctx.resolved_greeting_index,
            warnings: ctx.warnings,
            trace: nil,
            llm_options: ctx.llm_options,
          )
        end
      end
    end
  end
end
