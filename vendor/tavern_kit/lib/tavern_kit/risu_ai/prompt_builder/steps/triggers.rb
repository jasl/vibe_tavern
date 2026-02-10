# frozen_string_literal: true

module TavernKit
  module RisuAI
    module PromptBuilder
      module Steps
        # Step: triggers (tolerant).
        #
        # This step is intentionally minimal: it executes triggers against an
        # in-memory "chat" hash and stores the resulting scriptstate back into ctx
        # metadata for later macro expansion. UI/state parity remains app-owned.
        class Triggers < TavernKit::PromptBuilder::Step
          Config =
            Data.define do
              def self.from_hash(raw)
                return raw if raw.is_a?(self)

                raise ArgumentError, "triggers step config must be a Hash" unless raw.is_a?(Hash)
                raw.each_key do |key|
                  raise ArgumentError, "triggers step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
                end

                if raw.any?
                  raise ArgumentError, "triggers step does not accept step config keys: #{raw.keys.inspect}"
                end

                new
              end
            end

          def self.before(ctx, _config)
            triggers = ctx[:risuai_triggers]
            return unless triggers.is_a?(Array) && triggers.any?

            context = ctx.context
            chat_index =
              if context.respond_to?(:chat_index)
                context.chat_index.to_i
              elsif context.respond_to?(:[]) && context.key?(:chat_index)
                context[:chat_index].to_i
              else
                -1
              end

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
end
