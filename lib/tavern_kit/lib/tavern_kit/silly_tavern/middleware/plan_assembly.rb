# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Middleware
      # Wave 4: build the final Prompt::Plan.
      class PlanAssembly < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          preset = ctx.preset
          blocks = Array(ctx.blocks)

          # These "control prompts" are inserted late (after macro expansion),
          # so we expand them explicitly to keep behavior consistent.
          ctx.expander ||= TavernKit::SillyTavern::Macro::V2Engine.new
          env = TavernKit::SillyTavern::ExpanderVars.build(ctx)

          generation_type = ctx.generation_type.to_sym

          if ctx.group && generation_type != :impersonate
            blocks = append_control_prompt(
              blocks,
              ctx,
              content: preset.group_nudge_prompt,
              env: env,
              source: :group_nudge,
              slot: :group_nudge_prompt,
            )
          end

          if generation_type == :continue
            if preset.continue_prefill == true
              blocks = apply_continue_postfix(blocks, postfix: preset.continue_postfix)
            else
              blocks = append_control_prompt(
                blocks,
                ctx,
                content: preset.continue_nudge_prompt,
                env: env,
                source: :continue_nudge,
                slot: :continue_nudge_prompt,
              )
            end
          end

          if generation_type == :impersonate
            blocks = append_control_prompt(
              blocks,
              ctx,
              content: preset.impersonation_prompt,
              env: env,
              source: :impersonation_prompt,
              slot: :impersonation_prompt,
            )
          end

          ctx.blocks = blocks

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

          ctx.instrument(:stat, stage: :plan_assembly, key: :plan_blocks, value: ctx.blocks.size)
        end

        def append_control_prompt(blocks, ctx, content:, env:, source:, slot:)
          text = content.to_s
          return blocks if text.strip.empty?

          expanded =
            begin
              ctx.expander.expand(text, environment: env)
            rescue TavernKit::SillyTavern::MacroError => e
              ctx.warn("Macro expansion error in #{source}: #{e.class}: #{e.message}")
              text
            end

          blocks + [
            TavernKit::Prompt::Block.new(
              role: :system,
              content: expanded.to_s,
              slot: slot,
              token_budget_group: :system,
              removable: false,
              metadata: { source: source },
            ),
          ]
        end

        def apply_continue_postfix(blocks, postfix:)
          suffix = postfix.to_s
          return blocks if suffix.empty?

          idx = blocks.rindex { |b| b.enabled? && b.role == :assistant }
          return blocks if idx.nil?

          target = blocks[idx]
          new_content = target.content.to_s
          new_content += suffix unless new_content.end_with?(suffix)

          copy = blocks.dup
          copy[idx] = target.with(content: new_content, metadata: target.metadata.merge(source: :continue_prefill))
          copy
        end
      end
    end
  end
end
