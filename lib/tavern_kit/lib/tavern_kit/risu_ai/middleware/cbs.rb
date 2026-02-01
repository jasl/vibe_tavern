# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Wave 5f Stage 3: CBS macro expansion for all blocks.
      class CBS < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.blocks ||= []

          runtime = ctx.runtime
          chat_index = runtime ? runtime.chat_index.to_i : -1
          message_index = runtime ? runtime.message_index.to_i : inferred_message_index(ctx)
          rng_word = runtime ? runtime.rng_word.to_s : ""
          run_var = runtime ? (runtime.run_var == true) : true
          rm_var = runtime ? (runtime.rm_var == true) : false

          env_kwargs = {
            character: ctx.character,
            user: ctx.user,
            history: (ctx[:risuai_groups].is_a?(Hash) ? ctx[:risuai_groups][:chats] : nil),
            greeting_index: ctx.greeting_index,
            chat_index: chat_index,
            message_index: message_index,
            variables: ctx.variables_store,
            dialect: ctx.dialect,
            model_hint: ctx[:model_hint],
            toggles: runtime&.toggles,
            metadata: runtime&.metadata,
            run_var: run_var,
            rm_var: rm_var,
            rng_word: rng_word,
          }

          engine = ctx.expander || TavernKit::RisuAI::CBS::Engine.new

          ctx.blocks = Array(ctx.blocks).map do |block|
            next block unless block.is_a?(TavernKit::Prompt::Block)

            env = TavernKit::RisuAI::CBS::Environment.build(**env_kwargs.merge(role: block.role))
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
