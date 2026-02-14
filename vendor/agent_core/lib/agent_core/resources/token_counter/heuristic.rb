# frozen_string_literal: true

module AgentCore
  module Resources
    module TokenCounter
      # Character-based heuristic token counter.
      #
      # Always succeeds, never raises — intended as a zero-dependency
      # fallback when no real tokenizer is available.
      #
      # Default: 4.0 characters per token (conservative for English text
      # and most LLM tokenizers). Configurable per instance.
      #
      # @example
      #   counter = AgentCore::Resources::TokenCounter::Heuristic.new
      #   counter.count_text("Hello, world!") # => 4
      #
      # @example Tighter packing
      #   counter = AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: 2.5)
      class Heuristic < Base
        attr_reader :chars_per_token

        # @param chars_per_token [Float] Average characters per token
        def initialize(chars_per_token: 4.0)
          raise ArgumentError, "chars_per_token must be positive" unless chars_per_token > 0

          @chars_per_token = chars_per_token.to_f
        end

        # @param text [String, nil] The text to estimate
        # @return [Integer] Estimated token count
        def count_text(text)
          return 0 if text.nil? || text.empty?

          (text.length / chars_per_token).ceil
        end
      end
    end
  end
end
