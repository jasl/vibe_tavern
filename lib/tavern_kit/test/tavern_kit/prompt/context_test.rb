# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::ContextTest < Minitest::Test
  def test_default_values
    ctx = TavernKit::Prompt::Context.new
    assert_nil ctx.character
    assert_nil ctx.user
    assert_nil ctx.history
    assert_nil ctx.preset
    assert_equal :normal, ctx.generation_type
    assert_equal [], ctx.lore_books
    assert_equal({}, ctx.outlets)
    assert_equal({}, ctx.pinned_groups)
    assert_equal [], ctx.blocks
    assert_equal false, ctx.strict
    assert_equal false, ctx.strict?
    assert_nil ctx.instrumenter
    assert_nil ctx.current_stage
    assert_equal [], ctx.warnings
    assert_equal({}, ctx.metadata)
  end

  def test_initialize_with_attributes
    user = TavernKit::User.new(name: "Alice")
    ctx = TavernKit::Prompt::Context.new(user: user, user_message: "Hello!")
    assert_equal user, ctx.user
    assert_equal "Hello!", ctx.user_message
  end

  def test_unknown_keys_go_to_metadata
    ctx = TavernKit::Prompt::Context.new(custom_key: "value")
    assert_equal "value", ctx[:custom_key]
  end

  def test_metadata_access
    ctx = TavernKit::Prompt::Context.new
    ctx[:key] = "value"
    assert_equal "value", ctx[:key]
    assert ctx.key?(:key)
    assert_equal "value", ctx.fetch(:key)
  end

  def test_warn_collects_warnings
    ctx = TavernKit::Prompt::Context.new(warning_handler: nil)
    ctx.warn("test warning")
    assert_equal ["test warning"], ctx.warnings
  end

  def test_warn_in_strict_mode
    ctx = TavernKit::Prompt::Context.new(strict: true, warning_handler: nil)
    assert_equal true, ctx.strict?
    assert_raises(TavernKit::StrictModeError) do
      ctx.warn("strict error")
    end
    assert_equal ["strict error"], ctx.warnings
  end

  def test_validate_raises_without_character
    ctx = TavernKit::Prompt::Context.new(user: TavernKit::User.new(name: "Alice"))
    assert_raises(ArgumentError, /character/) { ctx.validate! }
  end

  def test_validate_raises_without_user
    char = TavernKit::Character.create(name: "Test")
    ctx = TavernKit::Prompt::Context.new(character: char)
    assert_raises(ArgumentError, /user/) { ctx.validate! }
  end

  def test_validate_passes_with_both
    char = TavernKit::Character.create(name: "Test")
    user = TavernKit::User.new(name: "Alice")
    ctx = TavernKit::Prompt::Context.new(character: char, user: user)
    assert_equal ctx, ctx.validate!
  end

  def test_dup_creates_independent_copy
    ctx = TavernKit::Prompt::Context.new(warning_handler: nil)
    ctx.warn("original")
    ctx.macro_vars = { foo: "bar" }
    ctx.pinned_groups["chat_history"] = [TavernKit::Prompt::Block.new(role: :user, content: "hi")]
    copy = ctx.dup
    copy.warn("copy")
    copy.macro_vars[:foo] = "changed"
    copy.pinned_groups["chat_history"] << TavernKit::Prompt::Block.new(role: :assistant, content: "yo")

    assert_equal ["original"], ctx.warnings
    assert_equal ["original", "copy"], copy.warnings
    assert_equal "bar", ctx.macro_vars[:foo]
    assert_equal "changed", copy.macro_vars[:foo]
    assert_equal 1, ctx.pinned_groups["chat_history"].length
    assert_equal 2, copy.pinned_groups["chat_history"].length
  end
end
