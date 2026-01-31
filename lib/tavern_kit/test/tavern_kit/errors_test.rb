# frozen_string_literal: true

require "test_helper"

class TavernKit::ErrorsTest < Minitest::Test
  def test_error_hierarchy
    assert TavernKit::Error < StandardError
    assert TavernKit::StrictModeError < TavernKit::Error
    assert TavernKit::InvalidCardError < TavernKit::Error
    assert TavernKit::UnsupportedVersionError < TavernKit::Error
    assert TavernKit::Png::ParseError < TavernKit::Error
    assert TavernKit::Png::WriteError < TavernKit::Error
    assert TavernKit::Lore::ParseError < TavernKit::Error
  end

  def test_errors_can_be_raised_and_rescued
    assert_raises(TavernKit::Error) { raise TavernKit::InvalidCardError, "bad card" }
    assert_raises(TavernKit::Error) { raise TavernKit::StrictModeError, "strict" }
    assert_raises(TavernKit::Error) { raise TavernKit::Png::ParseError, "png" }
    assert_raises(TavernKit::Error) { raise TavernKit::Png::WriteError, "write" }
    assert_raises(TavernKit::Error) { raise TavernKit::Lore::ParseError, "lore" }
  end

  def test_error_messages
    error = TavernKit::InvalidCardError.new("missing name field")
    assert_equal "missing name field", error.message
  end

  # --- SillyTavern Error Hierarchy Tests ---

  def test_silly_tavern_error_hierarchy
    assert TavernKit::SillyTavern::MacroError < TavernKit::Error
    assert TavernKit::SillyTavern::MacroSyntaxError < TavernKit::SillyTavern::MacroError
    assert TavernKit::SillyTavern::UnknownMacroError < TavernKit::SillyTavern::MacroError
    assert TavernKit::SillyTavern::UnconsumedMacroError < TavernKit::SillyTavern::MacroError
    assert TavernKit::SillyTavern::MacroRecursionError < TavernKit::SillyTavern::MacroError
    assert TavernKit::SillyTavern::MacroBlockError < TavernKit::SillyTavern::MacroError
    assert TavernKit::SillyTavern::InvalidInstructError < TavernKit::Error
    assert TavernKit::SillyTavern::LoreParseError < TavernKit::Lore::ParseError
  end

  def test_macro_error_with_attributes
    error = TavernKit::SillyTavern::MacroError.new("failed", macro_name: "user", position: 42)
    assert_equal "user", error.macro_name
    assert_equal 42, error.position
    assert_includes error.message, "failed"
    assert_includes error.message, "user"
    assert_includes error.message, "42"
  end

  def test_macro_error_without_attributes
    error = TavernKit::SillyTavern::MacroError.new("simple error")
    assert_nil error.macro_name
    assert_nil error.position
    assert_equal "simple error", error.message
  end

  def test_macro_syntax_error
    error = TavernKit::SillyTavern::MacroSyntaxError.new(
      "mismatched braces",
      macro_name: "if",
      position: 10
    )
    assert_raises(TavernKit::SillyTavern::MacroError) { raise error }
  end

  def test_unknown_macro_error
    error = TavernKit::SillyTavern::UnknownMacroError.new(
      "macro not registered",
      macro_name: "unknownMacro"
    )
    assert_equal "unknownMacro", error.macro_name
  end

  def test_unconsumed_macro_error
    error = TavernKit::SillyTavern::UnconsumedMacroError.new(
      "macros remain",
      remaining_macros: ["{{user}}", "{{char}}"]
    )
    assert_equal ["{{user}}", "{{char}}"], error.remaining_macros
  end

  def test_macro_recursion_error
    error = TavernKit::SillyTavern::MacroRecursionError.new(
      "max depth exceeded",
      depth: 15,
      max_depth: 10,
      macro_name: "getvar"
    )
    assert_equal 15, error.depth
    assert_equal 10, error.max_depth
    assert_includes error.message, "15"
    assert_includes error.message, "10"
  end

  def test_macro_block_error
    error = TavernKit::SillyTavern::MacroBlockError.new(
      "unclosed block",
      opening_tag: "{{if condition}}",
      expected_closing: "{{/if}}"
    )
    assert_equal "{{if condition}}", error.opening_tag
    assert_equal "{{/if}}", error.expected_closing
  end

  def test_invalid_instruct_error
    error = TavernKit::SillyTavern::InvalidInstructError.new("missing system prompt")
    assert_raises(TavernKit::Error) { raise error }
  end

  def test_lore_parse_error_hierarchy
    error = TavernKit::SillyTavern::LoreParseError.new("invalid world info format")
    assert_raises(TavernKit::Lore::ParseError) { raise error }
    assert_raises(TavernKit::Error) { raise error }
  end

  # --- RisuAI Error Hierarchy Tests ---

  def test_risuai_error_hierarchy
    assert TavernKit::RisuAI::CBSError < TavernKit::Error
    assert TavernKit::RisuAI::CBSSyntaxError < TavernKit::RisuAI::CBSError
    assert TavernKit::RisuAI::CBSStackOverflowError < TavernKit::RisuAI::CBSError
    assert TavernKit::RisuAI::DecoratorParseError < TavernKit::Error
    assert TavernKit::RisuAI::TriggerError < TavernKit::Error
    assert TavernKit::RisuAI::TriggerRecursionError < TavernKit::RisuAI::TriggerError
  end

  def test_risuai_cbs_error_includes_metadata
    error = TavernKit::RisuAI::CBSError.new("bad", position: 12, block_type: "when")
    assert_equal 12, error.position
    assert_equal "when", error.block_type
    assert_includes error.message, "bad"
    assert_includes error.message, "12"
    assert_includes error.message, "when"
  end

  def test_risuai_cbs_stack_overflow_error
    error = TavernKit::RisuAI::CBSStackOverflowError.new("overflow", depth: 21, max_depth: 20, position: 99)
    assert_equal 21, error.depth
    assert_equal 20, error.max_depth
    assert_includes error.message, "overflow"
    assert_includes error.message, "21"
    assert_includes error.message, "20"
    assert_includes error.message, "99"
  end

  def test_risuai_trigger_error_includes_metadata
    error = TavernKit::RisuAI::TriggerError.new("boom", trigger_type: "output", effect_type: "setvar")
    assert_equal "output", error.trigger_type
    assert_equal "setvar", error.effect_type
    assert_includes error.message, "boom"
    assert_includes error.message, "output"
    assert_includes error.message, "setvar"
  end

  def test_risuai_trigger_recursion_error
    error = TavernKit::RisuAI::TriggerRecursionError.new("loop", depth: 11, max_depth: 10)
    assert_equal 11, error.depth
    assert_equal 10, error.max_depth
    assert_includes error.message, "11"
    assert_includes error.message, "10"
  end
end
