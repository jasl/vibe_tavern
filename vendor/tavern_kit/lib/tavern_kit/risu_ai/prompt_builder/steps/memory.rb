# frozen_string_literal: true

module TavernKit
  module RisuAI
    module PromptBuilder
      module Steps
      # Memory integration (contract-only).
      #
      # This calls an application-provided adapter and inserts the returned
      # blocks into the `:memory` slot for TemplateCards.
      module Memory
        extend TavernKit::PromptBuilder::Step

        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "memory step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "memory step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "memory step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        def self.before(ctx, _config)
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

        class << self
          private

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
  end
end
