# frozen_string_literal: true

module TavernKit
  module RisuAI
    module PromptBuilder
      module Steps
      # Step: CBS macro expansion for all blocks.
      module CBS
        extend TavernKit::PromptBuilder::Step

        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "cbs step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "cbs step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "cbs step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        def self.before(ctx, _config)
          ctx.blocks ||= []

          context = ctx.context
          chat_index = context_int(context, :chat_index, default: -1)
          message_index = context_int(context, :message_index, default: inferred_message_index(ctx))
          rng_word = context_value(context, :rng_word, default: "").to_s
          run_var = context_value(context, :run_var, default: true) == true
          rm_var = context_value(context, :rm_var, default: false) == true

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
            toggles: context_value(context, :toggles, default: nil),
            metadata: context_value(context, :metadata, default: nil),
            cbs_conditions: context_value(context, :cbs_conditions, default: nil),
            modules: context_value(context, :modules, default: nil),
            run_var: run_var,
            rm_var: rm_var,
            rng_word: rng_word,
          }

          engine = ctx.expander || TavernKit::RisuAI::CBS::Engine.new

          ctx.blocks = Array(ctx.blocks).map do |block|
            next block unless block.is_a?(TavernKit::PromptBuilder::Block)

            env = TavernKit::RisuAI::CBS::Environment.build(**env_kwargs.merge(role: block.role))
            expanded = engine.expand(block.content.to_s, environment: env)
            block.with(content: expanded)
          end
        end

        class << self
          private

        def inferred_message_index(ctx)
          history = TavernKit::ChatHistory.wrap(ctx.history)
          history.size
        rescue ArgumentError
          0
        end

        def context_int(context, key, default:)
          value = context_value(context, key, default: default)
          value.to_i
        rescue StandardError
          default
        end

        def context_value(context, key, default:)
          return default unless context

          if context.respond_to?(key)
            value = context.public_send(key)
            return value.nil? ? default : value
          end

          return context[key] if context.respond_to?(:[]) && context.key?(key)

          default
        end
        end
      end
      end
    end
  end
end
