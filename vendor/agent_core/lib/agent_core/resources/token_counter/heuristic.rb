# frozen_string_literal: true

module AgentCore
  module Resources
    module TokenCounter
      # Character-based heuristic token counter.
      #
      # Counting always succeeds for any String/nil input. Invalid configuration
      # raises ArgumentError on initialization. Intended as a zero-dependency
      # fallback when no real tokenizer is available.
      #
      # Default: 4.0 characters per token (conservative for English text
      # and most LLM tokenizers). For non-ASCII characters (e.g., CJK),
      # this counter defaults to 1 char = 1 token to avoid severe underestimates.
      # Configurable per instance.
      #
      # @example
      #   counter = AgentCore::Resources::TokenCounter::Heuristic.new
      #   counter.count_text("Hello, world!") # => 4
      #
      # @example Tighter packing
      #   counter = AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: 2.5)
      class Heuristic < Base
        attr_reader :chars_per_token, :non_ascii_chars_per_token

        # @param chars_per_token [Float] Average characters per token
        # @param non_ascii_chars_per_token [Float] Average non-ASCII characters per token
        def initialize(chars_per_token: 4.0, non_ascii_chars_per_token: 1.0)
          raise ArgumentError, "chars_per_token must be positive" unless chars_per_token > 0
          raise ArgumentError, "non_ascii_chars_per_token must be positive" unless non_ascii_chars_per_token > 0

          @chars_per_token = chars_per_token.to_f
          @non_ascii_chars_per_token = non_ascii_chars_per_token.to_f
        end

        # @param text [String, nil] The text to estimate
        # @return [Integer] Estimated token count
        def count_text(text)
          return 0 if text.nil? || text.empty?

          ascii_chars = 0
          non_ascii_chars = 0

          text.each_char do |ch|
            if ch.ascii_only?
              ascii_chars += 1
            else
              non_ascii_chars += 1
            end
          end

          ascii_tokens = (ascii_chars / chars_per_token).ceil
          non_ascii_tokens = (non_ascii_chars / non_ascii_chars_per_token).ceil

          ascii_tokens + non_ascii_tokens
        end
      end
    end
  end
end
