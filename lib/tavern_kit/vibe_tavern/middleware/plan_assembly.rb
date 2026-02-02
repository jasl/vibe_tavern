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

          system_block = build_system_block(ctx)
          blocks << system_block if system_block

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

          post_history_block = build_post_history_block(ctx)
          blocks << post_history_block if post_history_block

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

        def build_system_block(ctx)
          # Explicit override (including nil/blank) wins.
          if ctx.key?(:system_template)
            return nil if ctx[:system_template].to_s.strip.empty?

            return build_template_block(ctx, ctx[:system_template], source: :system_template, slot: :system)
          end

          build_default_system_block(ctx)
        end

        def build_post_history_block(ctx)
          if ctx.key?(:post_history_template)
            return nil if ctx[:post_history_template].to_s.strip.empty?

            return build_template_block(
              ctx,
              ctx[:post_history_template],
              source: :post_history_template,
              slot: :post_history_instructions,
            )
          end

          text = ctx.character&.data&.post_history_instructions.to_s
          text = TavernKit::Utils.presence(text)
          return nil unless text

          TavernKit::Prompt::Block.new(
            role: :system,
            content: text,
            slot: :post_history_instructions,
            token_budget_group: :system,
            metadata: { source: :post_history_instructions },
          )
        end

        def build_template_block(ctx, template, source:, slot:)
          rendered =
            TavernKit::VibeTavern::LiquidMacros.render_for(
              ctx,
              template.to_s,
              strict: ctx.strict?,
              on_error: :passthrough,
            )

          text = TavernKit::Utils.presence(rendered)
          return nil unless text

          TavernKit::Prompt::Block.new(
            role: :system,
            content: text,
            slot: slot,
            token_budget_group: :system,
            metadata: { source: source },
          )
        end

        def build_default_system_block(ctx)
          char = ctx.character
          user = ctx.user

          return nil unless char || user

          parts = []
          parts << presence(char&.data&.system_prompt)

          char_name =
            if char&.respond_to?(:display_name)
              char.display_name.to_s
            elsif char&.respond_to?(:name)
              char.name.to_s
            else
              ""
            end
          char_name = TavernKit::Utils.presence(char_name)
          parts << "You are #{char_name}." if char_name

          parts << presence(char&.data&.description)
          parts << presence(char&.data&.personality)

          scenario = presence(char&.data&.scenario)
          parts << "Scenario:\n#{scenario}" if scenario

          persona = presence(user&.persona_text)
          parts << "User persona:\n#{persona}" if persona

          text = parts.compact.join("\n\n")
          text = TavernKit::Utils.presence(text)
          return nil unless text

          TavernKit::Prompt::Block.new(
            role: :system,
            content: text,
            slot: :system,
            token_budget_group: :system,
            metadata: { source: :default_system },
          )
        end

        def presence(value)
          TavernKit::Utils.presence(value)
        end
      end
    end
  end
end
