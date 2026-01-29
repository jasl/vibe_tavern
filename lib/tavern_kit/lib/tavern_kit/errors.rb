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

  module SillyTavern
    # Base error class for SillyTavern macro system errors.
    class MacroError < TavernKit::Error
      attr_reader :macro_name, :position

      def initialize(message, macro_name: nil, position: nil)
        @macro_name = macro_name
        @position = position

        parts = [message]
        parts << "macro: #{macro_name}" if macro_name
        parts << "at position: #{position}" if position
        super(parts.join(" (") + (")" * [parts.size - 1, 0].max))
      end
    end

    # Raised when a macro has invalid syntax (mismatched braces, invalid arguments, etc.)
    class MacroSyntaxError < MacroError; end

    # Raised when attempting to use an unregistered macro.
    class UnknownMacroError < MacroError; end

    # Raised when macro placeholders remain unconsumed after evaluation.
    # This indicates a macro failed to resolve properly.
    class UnconsumedMacroError < MacroError
      attr_reader :remaining_macros

      def initialize(message, remaining_macros: [], **kwargs)
        @remaining_macros = remaining_macros
        super(message, **kwargs)
      end
    end

    # Raised when macro recursion depth is exceeded.
    class MacroRecursionError < MacroError
      attr_reader :depth, :max_depth

      def initialize(message, depth:, max_depth:, **kwargs)
        @depth = depth
        @max_depth = max_depth
        super("#{message} (depth: #{depth}, max: #{max_depth})", **kwargs)
      end
    end

    # Raised when a scoped block macro is malformed (missing closing tag, etc.)
    class MacroBlockError < MacroError
      attr_reader :opening_tag, :expected_closing

      def initialize(message, opening_tag: nil, expected_closing: nil, **kwargs)
        @opening_tag = opening_tag
        @expected_closing = expected_closing
        super(message, **kwargs)
      end
    end

    # Raised when an instruct template is invalid or missing required fields.
    class InvalidInstructError < TavernKit::Error; end

    # Raised when World Info / Lorebook parsing fails with ST-specific issues.
    class LoreParseError < TavernKit::Lore::ParseError; end
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
