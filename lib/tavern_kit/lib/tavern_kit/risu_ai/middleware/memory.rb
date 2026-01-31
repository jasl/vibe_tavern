# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Wave 5f Stage 2: Memory Integration (contract-only).
      #
      # This calls an application-provided adapter and inserts the returned
      # blocks into the `:memory` slot for TemplateCards.
      class Memory < TavernKit::Prompt::Middleware::Base
        private

        def before(ctx)
          adapter = ctx[:risuai_memory_adapter]
          return if adapter.nil?
          return unless adapter.respond_to?(:integrate)

          groups = ctx[:risuai_groups]
          groups = {} unless groups.is_a?(Hash)

          input = coerce_input(ctx[:risuai_memory_input])

          result = adapter.integrate(input, context: ctx)
          unless result.is_a?(TavernKit::RisuAI::Memory::MemoryResult)
            raise ArgumentError, "memory adapter must return MemoryResult, got: #{result.class}"
          end

          blocks = Array(result.blocks)
          groups[:memory] = Array(groups[:memory]) + blocks

          ctx[:risuai_groups] = groups
          ctx[:risuai_memory_result] = result
        end

        def coerce_input(value)
          return value if value.is_a?(TavernKit::RisuAI::Memory::MemoryInput)

          h = value.is_a?(Hash) ? TavernKit::Utils.deep_stringify_keys(value) : {}
          TavernKit::RisuAI::Memory::MemoryInput.new(
            summaries: h["summaries"],
            pinned_memories: h["pinned_memories"],
            metadata: h["metadata"],
            budget_tokens: h["budget_tokens"],
          )
        end
      end
    end
  end
end
