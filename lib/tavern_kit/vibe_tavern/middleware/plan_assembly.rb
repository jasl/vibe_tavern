# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Middleware
      # Stage: build a minimal Prompt::Plan from history + user input.
      #
      # Initial goal: unblock Rails integration with a deterministic, typed
      # plan output. Higher-level behaviors (macros/lore/injection/trimming)
      # can be composed later without breaking the app-level entrypoint.
      class PlanAssembly < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.blocks = build_blocks(ctx)

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

          ctx.instrument(:stat, stage: :plan_assembly, key: :plan_blocks, value: ctx.blocks.size) if ctx.instrumenter
        end

        def build_blocks(ctx)
          blocks = []

          system_template = ctx[:system_template].to_s
          if !system_template.strip.empty?
            rendered =
              TavernKit::VibeTavern::LiquidMacros.render_for(
                ctx,
                system_template,
                strict: ctx.strict?,
                on_error: :passthrough,
              )

            rendered = rendered.to_s
            unless rendered.strip.empty?
              blocks << TavernKit::Prompt::Block.new(
                role: :system,
                content: rendered,
                slot: :system,
                token_budget_group: :system,
                metadata: { source: :system_template },
              )
            end
          end

          history = TavernKit::ChatHistory.wrap(ctx.history)
          history.each do |message|
            blocks << TavernKit::Prompt::Block.new(
              role: message.role,
              content: message.content.to_s,
              name: message.name,
              attachments: message.attachments,
              message_metadata: message.metadata,
              slot: :history,
              token_budget_group: :history,
              metadata: { source: :history },
            )
          end

          user_text = ctx.user_message.to_s
          unless user_text.strip.empty?
            blocks << TavernKit::Prompt::Block.new(
              role: :user,
              content: user_text,
              slot: :user_message,
              token_budget_group: :history,
              metadata: { source: :user_message },
            )
          end

          blocks
        end
      end
    end
  end
end
