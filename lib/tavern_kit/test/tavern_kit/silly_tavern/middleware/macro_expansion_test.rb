# frozen_string_literal: true

require "test_helper"

class TavernKit::SillyTavern::Middleware::MacroExpansionTest < Minitest::Test
  class BoomExpander
    def expand(_text, environment:)
      raise TavernKit::SillyTavern::MacroSyntaxError.new("boom", macro_name: "x", position: 0)
    end
  end

  def run_macro_expansion(ctx)
    TavernKit::Prompt::Pipeline.new do
      use TavernKit::SillyTavern::Middleware::MacroExpansion, name: :macro_expansion
    end.call(ctx)
  end

  def test_expands_basic_env_macros
    ctx = TavernKit::Prompt::Context.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob"),
      preset: TavernKit::SillyTavern::Preset.new,
      history: [],
      user_message: "",
    )

    ctx.blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "Hello {{user}} and {{char}}."),
    ]

    run_macro_expansion(ctx)

    assert_equal "Hello Bob and Alice.", ctx.blocks.first.content
  end

  def test_macro_errors_warn_and_preserve_original_content
    ctx = TavernKit::Prompt::Context.new(
      character: TavernKit::Character.create(name: "Alice"),
      user: TavernKit::User.new(name: "Bob"),
      preset: TavernKit::SillyTavern::Preset.new,
      history: [],
      user_message: "",
      expander: BoomExpander.new,
    )
    ctx.warning_handler = nil

    ctx.blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "Hi {{x}}"),
    ]

    run_macro_expansion(ctx)

    assert_equal "Hi {{x}}", ctx.blocks.first.content
    assert_equal 1, ctx.warnings.size
    assert_match(/Macro expansion error/, ctx.warnings.first)
  end
end
