# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::StateTest < Minitest::Test
  def test_default_values
    state = TavernKit::PromptBuilder::State.new
    assert_equal :normal, state.generation_type
    assert_equal [], state.lore_books
    assert_equal({}, state.outlets)
    assert_equal({}, state.pinned_groups)
    assert_equal [], state.blocks
    assert_equal false, state.strict
    assert_equal false, state.strict?
    assert_nil state.instrumenter
    assert_nil state.current_step
    assert_equal [], state.warnings
  end

  def test_warn_collects_warnings
    state = TavernKit::PromptBuilder::State.new(warning_handler: nil)
    state.warn("test warning")
    assert_equal ["test warning"], state.warnings
  end

  def test_warn_in_strict_mode
    state = TavernKit::PromptBuilder::State.new(strict: true, warning_handler: nil)
    assert_equal true, state.strict?

    assert_raises(TavernKit::StrictModeError) do
      state.warn("strict error")
    end

    assert_equal ["strict error"], state.warnings
  end

  def test_validate_raises_without_character
    state = TavernKit::PromptBuilder::State.new(user: TavernKit::User.new(name: "Alice"))
    assert_raises(ArgumentError, /character/) { state.validate! }
  end

  def test_validate_raises_without_user
    character = TavernKit::Character.create(name: "Test")
    state = TavernKit::PromptBuilder::State.new(character: character)
    assert_raises(ArgumentError, /user/) { state.validate! }
  end

  def test_validate_passes_with_both
    character = TavernKit::Character.create(name: "Test")
    user = TavernKit::User.new(name: "Alice")
    state = TavernKit::PromptBuilder::State.new(character: character, user: user)
    assert_equal state, state.validate!
  end

  def test_dup_creates_independent_copy
    state = TavernKit::PromptBuilder::State.new(warning_handler: nil)
    state.warn("original")
    state.macro_vars = { foo: "bar" }
    state.pinned_groups["chat_history"] = [TavernKit::PromptBuilder::Block.new(role: :user, content: "hi")]

    copy = state.dup
    copy.warn("copy")
    copy.macro_vars[:foo] = "changed"
    copy.pinned_groups["chat_history"] << TavernKit::PromptBuilder::Block.new(role: :assistant, content: "yo")

    assert_equal ["original"], state.warnings
    assert_equal ["original", "copy"], copy.warnings
    assert_equal "bar", state.macro_vars[:foo]
    assert_equal "changed", copy.macro_vars[:foo]
    assert_equal 1, state.pinned_groups["chat_history"].length
    assert_equal 2, copy.pinned_groups["chat_history"].length
  end

  def test_variables_store_helpers
    state = TavernKit::PromptBuilder::State.new
    assert_nil state.variables_store

    state.set_variable("x", "1")
    assert_kind_of TavernKit::VariablesStore::InMemory, state.variables_store
    assert_equal "1", state.variables_store.get("x", scope: :local)

    state.set_variables({ y: 2, z: "ok" }, scope: :global)
    assert_equal 2, state.variables_store.get("y", scope: :global)
    assert_equal "ok", state.variables_store.get("z", scope: :global)
  end

  def test_state_holds_prompt_builder_context
    context = TavernKit::PromptBuilder::Context.build({ language_policy: { enabled: true } }, type: :app)
    state = TavernKit::PromptBuilder::State.new(context: context)

    assert_equal context, state.context
    assert_equal true, state.context[:language_policy][:enabled]
  end

  def test_context_writer_rejects_non_context
    state = TavernKit::PromptBuilder::State.new
    assert_raises(ArgumentError) { state.context = {} }
  end
end
