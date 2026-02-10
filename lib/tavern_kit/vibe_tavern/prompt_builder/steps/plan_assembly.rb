# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module PromptBuilder
      module Steps
        # Step: build a minimal PromptBuilder::Plan from history + user input.
        #
        # Initial goal: unblock Rails integration with a deterministic, typed
        # plan output. Higher-level behaviors (macros/lore/injection/trimming)
        # can be composed later without breaking the app-level entrypoint.
        #
        # Current scope:
        # - optional system block (template or deterministic default)
        # - history passthrough
        # - optional post-history instructions
        # - user message
        class PlanAssembly < TavernKit::PromptBuilder::Step
          Config =
            Data.define(:default_system_text_builder) do
              def self.from_hash(raw)
                return raw if raw.is_a?(self)

                raise ArgumentError, "plan_assembly step config must be a Hash" unless raw.is_a?(Hash)
                raw.each_key do |key|
                  raise ArgumentError, "plan_assembly step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
                end

                unknown = raw.keys - %i[default_system_text_builder]
                raise ArgumentError, "unknown plan_assembly step config keys: #{unknown.inspect}" if unknown.any?

                builder = raw.fetch(:default_system_text_builder, nil)
                if builder && !builder.respond_to?(:call)
                  raise ArgumentError, "plan_assembly.default_system_text_builder must respond to #call"
                end

                new(default_system_text_builder: builder)
              end
            end

          DEFAULT_SYSTEM_TEXT_BUILDER =
            lambda do |ctx|
              char = ctx.character
              user = ctx.user

              return "" unless char || user

              parts = []
              parts << TavernKit::Utils.presence(char&.data&.system_prompt)

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

              parts << TavernKit::Utils.presence(char&.data&.description)
              parts << TavernKit::Utils.presence(char&.data&.personality)

              scenario = TavernKit::Utils.presence(char&.data&.scenario)
              parts << "Scenario:\n#{scenario}" if scenario

              persona = TavernKit::Utils.presence(user&.persona_text)
              parts << "User persona:\n#{persona}" if persona

              parts.compact.join("\n\n")
            end.freeze

          def self.before(ctx, config)
            ctx.blocks = build_blocks(ctx, config)

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

            ctx.instrument(:stat, step: ctx.current_step, key: :plan_blocks, value: ctx.blocks.size)
          end

          class << self
            private

            def build_blocks(ctx, config)
            blocks = []

            system_block = build_system_block(ctx, config)
            blocks << system_block if system_block

            history = TavernKit::ChatHistory.wrap(ctx.history)
            history.each do |message|
              blocks << TavernKit::PromptBuilder::Block.new(
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
              blocks << TavernKit::PromptBuilder::Block.new(
                role: :user,
                content: user_text,
                slot: :user_message,
                token_budget_group: :history,
                metadata: { source: :user_message },
              )
            end

            blocks
            end

            def build_system_block(ctx, config)
            # Explicit override (including nil/blank) wins.
            if ctx.key?(:system_template)
              return nil if ctx[:system_template].to_s.strip.empty?

              return build_template_block(ctx, ctx[:system_template], source: :system_template, slot: :system)
            end

            build_default_system_block(ctx, config)
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

            TavernKit::PromptBuilder::Block.new(
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

            TavernKit::PromptBuilder::Block.new(
              role: :system,
              content: text,
              slot: slot,
              token_budget_group: :system,
              metadata: { source: source },
            )
          end

            def build_default_system_block(ctx, config)
            char = ctx.character
            user = ctx.user

            return nil unless char || user

            text = build_default_system_text(ctx, default_system_text_builder: config.default_system_text_builder)
            return nil unless text

            TavernKit::PromptBuilder::Block.new(
              role: :system,
              content: text,
              slot: :system,
              token_budget_group: :system,
              metadata: { source: :default_system },
            )
          end

            def build_default_system_text(ctx, default_system_text_builder:)
            builder = default_system_text_builder || DEFAULT_SYSTEM_TEXT_BUILDER

            text = builder.call(ctx).to_s
            TavernKit::Utils.presence(text)
          rescue StandardError => e
            ctx.warn("plan_assembly.default_system_text_builder error (using default): #{e.class}: #{e.message}")
            text = DEFAULT_SYSTEM_TEXT_BUILDER.call(ctx).to_s
            TavernKit::Utils.presence(text)
            end
          end
        end
      end
    end
  end
end
