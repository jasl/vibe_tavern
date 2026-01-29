# frozen_string_literal: true

module TavernKit
  # Base error class for all TavernKit errors.
  class Error < StandardError; end

  # Raised when strict mode is enabled and a non-fatal warning is encountered.
  # This allows callers to opt into treating forward-compatibility warnings as hard errors.
  class StrictModeError < Error; end

  # Character card errors
  class InvalidCardError < Error; end
  class UnsupportedVersionError < Error; end

  module Png
    class ParseError < TavernKit::Error; end
    class WriteError < TavernKit::Error; end
  end

  module Lore
    class ParseError < TavernKit::Error; end
  end

  # Raised when a middleware stage fails during pipeline execution.
  #
  # Use the built-in exception cause chain (raise ..., cause: e) to retain the
  # original error for debugging.
  class PipelineError < Error
    attr_reader :stage

    def initialize(message, stage:)
      @stage = stage
      super("#{message} (stage: #{stage})")
    end
  end

  class MaxTokensExceededError < PipelineError
    attr_reader :estimated_tokens, :max_tokens, :reserve_tokens, :limit_tokens

    def initialize(estimated_tokens:, max_tokens:, reserve_tokens: 0, stage:)
      @estimated_tokens = Integer(estimated_tokens)
      @max_tokens = Integer(max_tokens)
      @reserve_tokens = Integer(reserve_tokens)
      @limit_tokens = [@max_tokens - @reserve_tokens, 0].max

      super(
        format(
          "Prompt estimated tokens %d exceeded limit %d (max_tokens: %d, reserve_tokens: %d)",
          @estimated_tokens,
          @limit_tokens,
          @max_tokens,
          @reserve_tokens,
        ),
        stage: stage,
      )
    end
  end
end
