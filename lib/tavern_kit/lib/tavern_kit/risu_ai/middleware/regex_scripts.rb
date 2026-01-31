# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Wave 5f Stage 3: Regex scripts (request-time modifications).
      #
      # This applies scripts in `ctx[:risuai_regex_scripts]` to every block's
      # content in `mode: :request` (tolerant; no-op when none are configured).
      class RegexScripts < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          ctx.blocks ||= []

          scripts = ctx[:risuai_regex_scripts]
          return unless scripts.is_a?(Array) && scripts.any?

          risu = ctx[:risuai].is_a?(Hash) ? ctx[:risuai] : {}
          chat_id = (risu[:chat_index] || risu["chat_index"] || -1).to_i

          history = TavernKit::ChatHistory.wrap(ctx.history).to_a
          history_hashes = history.map { |m| { role: m.role.to_s, data: m.content.to_s } }

          ctx.blocks = Array(ctx.blocks).map do |block|
            next block unless block.is_a?(TavernKit::Prompt::Block)

            out = TavernKit::RisuAI::RegexScripts.apply(
              block.content.to_s,
              scripts,
              mode: :request,
              chat_id: chat_id,
              history: history_hashes,
              role: block.role.to_s,
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
