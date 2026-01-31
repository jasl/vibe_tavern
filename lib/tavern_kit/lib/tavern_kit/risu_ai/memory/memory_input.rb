# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Memory
      MemoryInput = Data.define(
        :summaries,       # Array<String>
        :pinned_memories, # Array<String>
        :metadata,        # Hash
        :budget_tokens,   # Integer, nil
      ) do
        def initialize(summaries: nil, pinned_memories: nil, metadata: nil, budget_tokens: nil)
          summaries = Array(summaries).map(&:to_s)
          pinned_memories = Array(pinned_memories).map(&:to_s)
          metadata = (metadata || {})
          raise ArgumentError, "metadata must be a Hash" unless metadata.is_a?(Hash)

          budget_tokens = budget_tokens.nil? ? nil : Integer(budget_tokens)

          super(
            summaries: summaries.freeze,
            pinned_memories: pinned_memories.freeze,
            metadata: metadata.dup.freeze,
            budget_tokens: budget_tokens,
          )
        end
      end
    end
  end
end
