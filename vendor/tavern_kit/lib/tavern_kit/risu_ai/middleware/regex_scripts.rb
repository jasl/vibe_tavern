# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Stage: regex scripts (request-time modifications).
      #
      # This applies scripts in `ctx[:risuai_regex_scripts]` to every block's
      # content in `mode: :request` (tolerant; no-op when none are configured).
      class RegexScripts < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.blocks ||= []

          scripts = ctx[:risuai_regex_scripts]
          return unless scripts.is_a?(Array) && scripts.any?

          runtime = ctx.runtime
          chat_id = runtime ? runtime.chat_index.to_i : -1
          rng_word = runtime ? runtime.rng_word.to_s : ""

          history = TavernKit::ChatHistory.wrap(ctx.history).to_a
          history_hashes = history.map { |m| { role: m.role.to_s, data: m.content.to_s } }
          message_index = runtime ? runtime.message_index.to_i : history_hashes.length

          ctx.blocks = Array(ctx.blocks).map do |block|
            next block unless block.is_a?(TavernKit::Prompt::Block)

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
              toggles: runtime&.toggles,
              metadata: runtime&.metadata,
              cbs_conditions: runtime&.cbs_conditions,
              modules: runtime&.modules,
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
      end
    end
  end
end
