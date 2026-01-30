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
          ctx.llm_options = build_llm_options(ctx, preset, env: env)

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
              blocks = apply_continue_prefill(blocks, ctx, preset, env: env)
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
            llm_options: ctx.llm_options,
          )

          ctx.instrument(:stat, stage: :plan_assembly, key: :plan_blocks, value: ctx.blocks.size)
        end

        def build_llm_options(ctx, preset, env:)
          return {} unless claude_source?(ctx)

          type = ctx.generation_type.to_sym

          # ST parity: don't add a prefill on quiet gens (summarization) and when using continue prefill.
          return {} if type == :quiet
          return {} if type == :continue && preset.continue_prefill == true

          prefill =
            if type == :impersonate
              preset.assistant_impersonation.to_s
            else
              preset.assistant_prefill.to_s
            end

          prefill = expand_control_text(ctx, env: env, content: prefill, source: :assistant_prefill)
          prefill = prefill.to_s
          return {} if prefill.strip.empty?

          { assistant_prefill: prefill }
        end

        def claude_source?(ctx)
          meta = ctx.respond_to?(:metadata) ? ctx.metadata : {}
          acc = TavernKit::Utils::HashAccessor.wrap(meta)
          src = acc.fetch(:chat_completion_source, :chatCompletionSource, default: nil).to_s.strip.downcase
          src == "claude"
        end

        def append_control_prompt(blocks, ctx, content:, env:, source:, slot:)
          text = content.to_s
          return blocks if text.strip.empty?

          expanded = expand_control_text(ctx, env: env, content: text, source: source)

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

        def apply_continue_prefill(blocks, ctx, preset, env:)
          suffix = preset.continue_postfix.to_s
          assistant_prefill = preset.assistant_prefill.to_s

          idx = blocks.rindex { |b| b.enabled? && b.role == :assistant }
          return blocks if idx.nil?

          target = blocks[idx]
          new_content = target.content.to_s

          # Claude source parity: when using continue prefill, assistant_prefill is applied
          # by prepending it to the message to be continued, not via request options.
          if claude_source?(ctx)
            expanded = expand_control_text(ctx, env: env, content: assistant_prefill, source: :assistant_prefill)
            expanded = expanded.to_s.strip
            if !expanded.empty? && !new_content.start_with?(expanded)
              new_content = [expanded, new_content].reject(&:empty?).join("\n\n")
            end
          end

          new_content += suffix unless suffix.empty? || new_content.end_with?(suffix)

          copy = blocks.dup
          copy[idx] = target.with(content: new_content, metadata: target.metadata.merge(source: :continue_prefill))
          copy
        end

        def expand_control_text(ctx, env:, content:, source:)
          text = content.to_s
          return "" if text.empty?

          ctx.expander.expand(text, environment: env)
        rescue TavernKit::SillyTavern::MacroError => e
          ctx.warn("Macro expansion error in #{source}: #{e.class}: #{e.message}")
          text
        end
      end
    end
  end
end
