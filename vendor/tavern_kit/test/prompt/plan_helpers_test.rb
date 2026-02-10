# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::PlanHelpersTest < Minitest::Test
  def test_with_blocks_replaces_blocks_without_affecting_metadata
    original =
      TavernKit::Prompt::Plan.new(
        blocks: [
          TavernKit::Prompt::Block.new(role: :system, content: "S", slot: :system),
        ],
        llm_options: { temperature: 0.1 },
        warnings: ["warn"],
      )

    updated =
      original.with_blocks(
        [
          TavernKit::Prompt::Block.new(role: :user, content: "U", slot: :user_message),
        ],
      )

    refute_same original, updated
    assert_equal [:user_message], updated.blocks.map(&:slot)
    assert_equal original.llm_options, updated.llm_options
    assert_equal original.warnings, updated.warnings
  end

  def test_insert_before_and_after_by_slot
    plan =
      TavernKit::Prompt::Plan.new(
        blocks: [
          TavernKit::Prompt::Block.new(role: :system, content: "S", slot: :system),
          TavernKit::Prompt::Block.new(role: :user, content: "U", slot: :user_message),
        ],
      )

    marker = TavernKit::Prompt::Block.new(role: :system, content: "LP", slot: :language_policy)

    before = plan.insert_before(slot: :user_message, block: marker)
    assert_equal %i[system language_policy user_message], before.blocks.map(&:slot)

    after = plan.insert_after(slot: :system, block: marker)
    assert_equal %i[system language_policy user_message], after.blocks.map(&:slot)
  end

  def test_insert_appends_when_slot_is_missing
    plan =
      TavernKit::Prompt::Plan.new(
        blocks: [
          TavernKit::Prompt::Block.new(role: :system, content: "S", slot: :system),
          TavernKit::Prompt::Block.new(role: :user, content: "U", slot: :user_message),
        ],
      )

    marker = TavernKit::Prompt::Block.new(role: :system, content: "X", slot: :x)

    updated = plan.insert_before(slot: :missing, block: marker)
    assert_equal %i[system user_message x], updated.blocks.map(&:slot)
  end
end
