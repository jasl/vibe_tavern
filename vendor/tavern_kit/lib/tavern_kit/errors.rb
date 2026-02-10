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

        msg = message.to_s
        meta = []
        meta << "macro=#{macro_name}" if macro_name
        meta << "position=#{position}" if position

        super(meta.any? ? "#{msg} (#{meta.join(", ")})" : msg)
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
        @remaining_macros = Array(remaining_macros).map(&:to_s).freeze
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

  module RisuAI
    # Base error class for RisuAI CBS parsing/evaluation failures.
    class CBSError < TavernKit::Error
      attr_reader :position, :block_type

      def initialize(message, position: nil, block_type: nil)
        @position = position
        @block_type = block_type

        msg = message.to_s
        meta = []
        meta << "position=#{position}" if position
        meta << "block_type=#{block_type}" if block_type

        super(meta.any? ? "#{msg} (#{meta.join(", ")})" : msg)
      end
    end

    # Raised when a CBS template has invalid syntax (e.g., an unclosed block).
    class CBSSyntaxError < CBSError; end

    # Raised when CBS function call depth exceeds the configured limit.
    class CBSStackOverflowError < CBSError
      attr_reader :depth, :max_depth

      def initialize(message, depth:, max_depth:, **kwargs)
        @depth = Integer(depth)
        @max_depth = Integer(max_depth)
        super("#{message} (depth: #{@depth}, max: #{@max_depth})", **kwargs)
      end
    end

    # Raised when parsing inline decorators fails.
    class DecoratorParseError < TavernKit::Error; end

    # Raised when the trigger system encounters an unrecoverable error.
    class TriggerError < TavernKit::Error
      attr_reader :trigger_type, :effect_type

      def initialize(message, trigger_type: nil, effect_type: nil)
        @trigger_type = trigger_type
        @effect_type = effect_type

        msg = message.to_s
        meta = []
        meta << "trigger_type=#{trigger_type}" if trigger_type
        meta << "effect_type=#{effect_type}" if effect_type

        super(meta.any? ? "#{msg} (#{meta.join(", ")})" : msg)
      end
    end

    # Raised when trigger recursion depth exceeds the configured limit.
    class TriggerRecursionError < TriggerError
      attr_reader :depth, :max_depth

      def initialize(message, depth:, max_depth:, **kwargs)
        @depth = Integer(depth)
        @max_depth = Integer(max_depth)
        super("#{message} (depth: #{@depth}, max: #{@max_depth})", **kwargs)
      end
    end
  end

  module Archive
    # Base error for archive/package import failures (e.g. ZIP-based formats).
    class ParseError < TavernKit::Error; end

    # Raised when a ZIP container is malformed or violates safety limits.
    class ZipError < ParseError; end

    # Raised when importing a BYAF archive fails.
    class ByafParseError < ParseError; end

    # Raised when importing a CHARX archive fails.
    class CharXParseError < ParseError; end
  end

  # Raised when a step fails during pipeline execution.
  #
  # Use the built-in exception cause chain (raise ..., cause: e) to retain the
  # original error for debugging.
  class PipelineError < Error
    attr_reader :step

    def initialize(message, step:)
      @step = step
      super("#{message} (step: #{step})")
    end
  end

  class MaxTokensExceededError < PipelineError
    attr_reader :estimated_tokens, :max_tokens, :reserve_tokens, :limit_tokens

    def initialize(estimated_tokens:, max_tokens:, reserve_tokens: 0, step:)
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
        step: step,
      )
    end
  end
end
