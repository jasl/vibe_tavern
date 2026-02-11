# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
      # ST token budget enforcement (delegates to Core Trimmer).
      module Trimming
        extend TavernKit::PromptBuilder::Step

        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "trimming step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "trimming step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "trimming step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        def self.before(ctx, _config)
          preset = ctx.preset

          max_tokens = preset.context_window_tokens.to_i
          reserve_tokens = preset.reserved_response_tokens.to_i
          overhead = preset.message_token_overhead.to_i
          model_hint = ctx[:model_hint]

          result = TavernKit::Trimmer.trim(
            ctx.blocks,
            strategy: :group_order,
            max_tokens: max_tokens,
            reserve_tokens: reserve_tokens,
            token_estimator: ctx.token_estimator,
            model_hint: model_hint,
            message_overhead_tokens: overhead,
            step: ctx.current_step,
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

          if ctx.token_estimator.respond_to?(:describe)
            ctx.instrument(:stat, step: ctx.current_step, key: :token_estimator) do
              { value: ctx.token_estimator.describe(model_hint: model_hint) }
            end
          end

          ctx.instrument(:stat, step: ctx.current_step, key: :budget_tokens, value: result.report.budget_tokens)
          ctx.instrument(:stat, step: ctx.current_step, key: :initial_tokens, value: result.report.initial_tokens)
          ctx.instrument(:stat, step: ctx.current_step, key: :final_tokens, value: result.report.final_tokens)
          ctx.instrument(:stat, step: ctx.current_step, key: :eviction_count, value: result.report.eviction_count)
        end

        class << self
          private

        def build_plan(ctx, trace:, trim_report:)
          TavernKit::PromptBuilder::Plan.new(
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
  end
end
