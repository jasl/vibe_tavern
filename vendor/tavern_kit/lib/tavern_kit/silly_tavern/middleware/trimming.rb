# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # ST token budget enforcement (delegates to Core Trimmer).
      class Trimming < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          preset = ctx.preset

          max_tokens = preset.context_window_tokens.to_i
          reserve_tokens = preset.reserved_response_tokens.to_i
          overhead = preset.message_token_overhead.to_i

          result = TavernKit::Trimmer.trim(
            ctx.blocks,
            strategy: :group_order,
            max_tokens: max_tokens,
            reserve_tokens: reserve_tokens,
            token_estimator: ctx.token_estimator,
            message_overhead_tokens: overhead,
            stage: :trimming,
          )

          ctx.blocks = TavernKit::Trimmer.apply(ctx.blocks, result)
          ctx.trim_report = result.report

          ctx.plan = build_plan(ctx, trace: nil, trim_report: ctx.trim_report)

          if ctx.instrumenter && ctx.instrumenter.respond_to?(:to_trace)
            fingerprint = ctx.plan.fingerprint(
              dialect: (ctx.dialect || :openai),
              squash_system_messages: preset.squash_system_messages == true,
            )
            trace = ctx.instrumenter.to_trace(fingerprint: fingerprint)
            ctx.plan = build_plan(ctx, trace: trace, trim_report: ctx.trim_report)
          end

          if ctx.instrumenter
            ctx.instrument(:stat, stage: :trimming, key: :budget_tokens, value: result.report.budget_tokens)
            ctx.instrument(:stat, stage: :trimming, key: :initial_tokens, value: result.report.initial_tokens)
            ctx.instrument(:stat, stage: :trimming, key: :final_tokens, value: result.report.final_tokens)
            ctx.instrument(:stat, stage: :trimming, key: :eviction_count, value: result.report.eviction_count)
          end
        end

        def build_plan(ctx, trace:, trim_report:)
          TavernKit::Prompt::Plan.new(
            blocks: ctx.blocks,
            outlets: ctx.outlets,
            lore_result: ctx.lore_result,
            trim_report: trim_report,
            greeting: ctx.resolved_greeting,
            greeting_index: ctx.resolved_greeting_index,
            warnings: ctx.warnings,
            trace: trace,
            llm_options: ctx.llm_options,
          )
        end
      end
    end
  end
end
