# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Wave 5f Stage 3: Triggers (tolerant).
      #
      # This middleware is intentionally minimal: it executes triggers against an
      # in-memory "chat" hash and stores the resulting scriptstate back into ctx
      # metadata. Full UI/state parity is implemented incrementally in Wave 5.
      class Triggers < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          triggers = ctx[:risuai_triggers]
          return unless triggers.is_a?(Array) && triggers.any?

          runtime = ctx.runtime
          chat_index = runtime ? runtime.chat_index.to_i : -1

          ctx.variables_store!

          history = TavernKit::ChatHistory.wrap(ctx.history).to_a
          messages = history.map { |m| { role: m.role.to_s, data: m.content.to_s } }

          chat = {
            chatIndex: chat_index,
            fmIndex: ctx.greeting_index.nil? ? -1 : ctx.greeting_index.to_i,
            character: ctx.character,
            message: messages,
            # Prefer the Core Store as the scriptstate backend so CBS/lore/triggers
            # all share one source of truth.
            variables: ctx.variables_store,
            token_estimator: ctx.token_estimator,
            model_hint: ctx[:model_hint],
            scriptstate: {},
          }

          chat = TavernKit::RisuAI::Triggers.run_all(triggers, chat: chat).chat

          ctx[:risuai_scriptstate] = chat[:scriptstate] if chat.is_a?(Hash)
          ctx[:risuai_chat_state] = chat
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
