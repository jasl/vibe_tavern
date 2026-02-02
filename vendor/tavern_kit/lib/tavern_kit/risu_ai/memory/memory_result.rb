# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Memory
      MemoryResult = Data.define(
        :blocks,           # Array<Prompt::Block>
        :tokens_used,      # Integer
        :compression_type, # Symbol, nil
      ) do
        def initialize(blocks:, tokens_used: 0, compression_type: nil)
          blocks = Array(blocks)
          unless blocks.all? { |b| b.is_a?(TavernKit::Prompt::Block) }
            raise ArgumentError, "blocks must be an Array<Prompt::Block>"
          end

          tokens_used = Integer(tokens_used)
          compression_type = compression_type.nil? ? nil : compression_type.to_sym

          super(
            blocks: blocks.freeze,
            tokens_used: tokens_used,
            compression_type: compression_type,
          )
        end
      end
    end
  end
end
