# frozen_string_literal: true

module TavernKit
  module RisuAI
    module PromptBuilder
      module Steps
      # Final step: build a PromptBuilder::Plan from accumulated blocks.
      module PlanAssembly
        extend TavernKit::PromptBuilder::Step

        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "plan_assembly step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "plan_assembly step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "plan_assembly step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        def self.before(ctx, _config)
          ctx.blocks ||= []

          ctx.plan = TavernKit::PromptBuilder::Plan.new(
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
end
