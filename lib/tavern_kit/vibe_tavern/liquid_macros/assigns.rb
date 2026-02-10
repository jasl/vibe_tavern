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
          runtime = runtime_from(ctx)

          runtime_data = runtime ? runtime.to_h : {}
          runtime_hash = TavernKit::Utils.deep_stringify_keys(runtime_data)

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
            "runtime" => runtime_hash,
            "chat_index" => runtime_data[:chat_index],
            "message_index" => runtime_data[:message_index],
            "model" => runtime_data[:model],
            "role" => runtime_data[:role],
          }
        end

        def runtime_from(ctx)
          runtime = ctx.respond_to?(:runtime) ? ctx.runtime : nil
          return runtime if runtime.is_a?(TavernKit::PromptBuilder::Context)
          return TavernKit::PromptBuilder::Context.build(runtime, type: :app) if runtime.is_a?(Hash)

          return nil unless ctx.respond_to?(:key?) && ctx.key?(:runtime)

          TavernKit::PromptBuilder::Context.build(ctx[:runtime], type: :app)
        end
        private_class_method :runtime_from

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
