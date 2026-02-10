# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module LiquidMacros
      # Centralized, test-backed contract for which values are exposed to Liquid.
      #
      # The goal is to keep template inputs stable and reviewable as the Rails
      # rewrite evolves.
      module Assigns
        module_function

        # Build Liquid assigns from a prompt-building Context.
        #
        # @param ctx [TavernKit::PromptBuilder::Context]
        # @return [Hash{String => Object}]
        def build(ctx)
          character = ctx.respond_to?(:character) ? ctx.character : nil
          user = ctx.respond_to?(:user) ? ctx.user : nil
          context = context_from(ctx)

          context_data = context ? context.to_h : {}
          context_hash = TavernKit::Utils.deep_stringify_keys(context_data)

          {
            "char" => char_name(character),
            "user" => user_name(user),
            "description" => presence(character&.data&.description),
            "personality" => presence(character&.data&.personality),
            "scenario" => presence(character&.data&.scenario),
            "persona" => presence(user&.persona_text),
            "system_prompt" => presence(character&.data&.system_prompt),
            "post_history_instructions" => presence(character&.data&.post_history_instructions),
            "mes_examples" => presence(character&.data&.mes_example),
            "context" => context_hash,
            "chat_index" => context_data[:chat_index],
            "message_index" => context_data[:message_index],
            "model" => context_data[:model],
            "role" => context_data[:role],
          }
        end

        def context_from(ctx)
          return ctx if ctx.is_a?(TavernKit::PromptBuilder::Context)

          context = ctx.respond_to?(:context) ? ctx.context : nil
          return context if context.is_a?(TavernKit::PromptBuilder::Context)
          return TavernKit::PromptBuilder::Context.build(context, type: :app) if context.is_a?(Hash)
          nil
        end
        private_class_method :context_from

        def char_name(character)
          return nil unless character

          if character.respond_to?(:display_name)
            character.display_name.to_s
          elsif character.respond_to?(:name)
            character.name.to_s
          else
            character.to_s
          end
        end
        private_class_method :char_name

        def user_name(user)
          return nil unless user
          return user.name.to_s if user.respond_to?(:name)

          user.to_s
        end
        private_class_method :user_name

        def presence(value)
          TavernKit::Utils.presence(value)
        end
        private_class_method :presence
      end
    end
  end
end
