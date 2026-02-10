# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::ContextTest < Minitest::Test
  def test_default_values
    context = TavernKit::PromptBuilder::Context.new

    assert_nil context.type
    assert_nil context.id
    assert_equal({}, context.to_h)
    assert_equal({}, context.module_configs)
  end

  def test_build_normalizes_hash_keys
    context = TavernKit::PromptBuilder::Context.build({ "chatIndex" => 1, message_index: 2 }, type: :app, id: 42)

    assert_equal :app, context.type
    assert_equal "42", context.id
    assert_equal({ chat_index: 1, message_index: 2 }, context.to_h)
    assert_equal 1, context[:chat_index]
  end

  def test_new_normalizes_hash_keys
    context = TavernKit::PromptBuilder::Context.new({ "chatIndex" => 1 })
    assert_equal({ chat_index: 1 }, context.to_h)
  end

  def test_blank_keys_are_dropped
    context = TavernKit::PromptBuilder::Context.build({ nil => 1, "" => 2, " " => 3, "ok" => 4 })
    assert_equal({ ok: 4 }, context.to_h)
  end

  def test_module_configs_from_argument_override_data
    context =
      TavernKit::PromptBuilder::Context.new(
        { module_configs: { ignored: { enabled: true } } },
        module_configs: {
          language_policy: { enabled: true },
        },
      )

    assert_equal({ language_policy: { enabled: true } }, context.module_configs)
    refute context.key?(:module_configs)
  end

  def test_module_configs_are_normalized
    context =
      TavernKit::PromptBuilder::Context.new(
        module_configs: {
          "language-policy" => { enabled: true },
        },
      )

    assert_equal({ language_policy: { enabled: true } }, context.module_configs)
  end

  def test_module_configs_require_symbol_keys
    error =
      assert_raises(ArgumentError) do
        TavernKit::PromptBuilder::Context.new(
          module_configs: {
            language_policy: { "enabled" => true },
          },
        )
      end

    assert_match(/must be Symbols/, error.message)
  end

  def test_metadata_reader_helpers
    context = TavernKit::PromptBuilder::Context.new(chat_index: 123)
    assert_equal 123, context.fetch(:chat_index)
    assert context.key?(:chat_index)
    assert_nil context[:missing]
  end
end
