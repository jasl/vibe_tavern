# frozen_string_literal: true

module TavernKit
  module RisuAI
    module PromptBuilder
      module Steps
      # Step: regex scripts (request-time modifications).
      #
      # This applies scripts in `ctx[:risuai_regex_scripts]` to every block's
      # content in `mode: :request` (tolerant; no-op when none are configured).
      class RegexScripts < TavernKit::PromptBuilder::Step
        private

        def before(ctx)
          ctx.blocks ||= []

          scripts = ctx[:risuai_regex_scripts]
          return unless scripts.is_a?(Array) && scripts.any?

          context = ctx.context
          chat_id = context_int(context, :chat_index, default: -1)
          rng_word = context_value(context, :rng_word, default: "").to_s

          history = TavernKit::ChatHistory.wrap(ctx.history).to_a
          history_hashes = history.map { |m| { role: m.role.to_s, data: m.content.to_s } }
          message_index = context_int(context, :message_index, default: history_hashes.length)

          ctx.blocks = Array(ctx.blocks).map do |block|
            next block unless block.is_a?(TavernKit::PromptBuilder::Block)

            env = TavernKit::RisuAI::CBS::Environment.build(
              character: ctx.character,
              user: ctx.user,
              history: history_hashes,
              greeting_index: ctx.greeting_index,
              chat_index: chat_id,
              message_index: message_index,
              variables: ctx.variables_store,
              dialect: ctx.dialect,
              model_hint: ctx[:model_hint],
              toggles: context_value(context, :toggles, default: nil),
              metadata: context_value(context, :metadata, default: nil),
              cbs_conditions: context_value(context, :cbs_conditions, default: nil),
              modules: context_value(context, :modules, default: nil),
              run_var: false,
              rm_var: false,
              rng_word: rng_word,
              role: block.role.to_s,
            )

            out = TavernKit::RisuAI::RegexScripts.apply(
              block.content.to_s,
              scripts,
              mode: :request,
              chat_id: chat_id,
              history: history_hashes,
              role: block.role.to_s,
              environment: env,
            )

            block.with(content: out)
          end
        rescue ArgumentError
          # Tolerant: if history can't be wrapped, skip repeat_back.
          nil
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
