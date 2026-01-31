# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Memory
      # Interface-only adapter for memory integration (Wave 5g).
      #
      # Concrete adapters live in the application layer (vector DB / summaries /
      # compression algorithms).
      class Base
        # @param input [MemoryInput]
        # @param context [Prompt::Context]
        # @return [MemoryResult]
        def integrate(input, context:) = raise NotImplementedError
      end
    end
  end
end
