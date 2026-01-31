# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Wave 5f Stage 3: CBS macro expansion for all blocks.
      class CBS < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.blocks ||= []

          risu = ctx[:risuai].is_a?(Hash) ? ctx[:risuai] : {}
          chat_index = (risu[:chat_index] || risu["chat_index"] || 0).to_i
          message_index = (risu[:message_index] || risu["message_index"] || inferred_message_index(ctx)).to_i

          env = TavernKit::RisuAI::CBS::Environment.build(
            character: ctx.character,
            user: ctx.user,
            chat_index: chat_index,
            message_index: message_index,
            variables: ctx.variables_store,
            dialect: ctx.dialect,
            model_hint: ctx[:model_hint],
            toggles: (risu[:toggles] || risu["toggles"]),
          )

          engine = ctx.expander || TavernKit::RisuAI::CBS::Engine.new

          ctx.blocks = Array(ctx.blocks).map do |block|
            next block unless block.is_a?(TavernKit::Prompt::Block)

            expanded = engine.expand(block.content.to_s, environment: env)
            block.with(content: expanded)
          end
        end

        def inferred_message_index(ctx)
          history = TavernKit::ChatHistory.wrap(ctx.history)
          history.size
        rescue ArgumentError
          0
        end
      end
    end
  end
end
