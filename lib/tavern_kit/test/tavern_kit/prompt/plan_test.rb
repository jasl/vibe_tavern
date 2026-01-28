# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::PlanTest < Minitest::Test
  def test_empty_plan
    plan = TavernKit::Prompt::Plan.new(blocks: [])
    assert_equal 0, plan.size
    assert_equal 0, plan.enabled_size
    assert_equal [], plan.messages
    assert_equal [], plan.warnings
    refute plan.greeting?
  end

  def test_plan_with_blocks
    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "System prompt"),
      TavernKit::Prompt::Block.new(role: :user, content: "Hello!"),
      TavernKit::Prompt::Block.new(role: :assistant, content: "Hi there!"),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    assert_equal 3, plan.size
    assert_equal 3, plan.enabled_size
    assert_equal 3, plan.messages.size
  end

  def test_enabled_blocks_filters_disabled
    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "Active"),
      TavernKit::Prompt::Block.new(role: :system, content: "Disabled", enabled: false),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    assert_equal 2, plan.size
    assert_equal 1, plan.enabled_size
    assert_equal "Active", plan.enabled_blocks.first.content
  end

  def test_to_messages_openai_format
    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "System prompt"),
      TavernKit::Prompt::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    msgs = plan.to_messages(dialect: :openai)
    assert_kind_of Array, msgs
    assert_equal 2, msgs.size
    assert_equal :system, msgs[0][:role]
    assert_equal "Hello!", msgs[1][:content]
  end

  def test_squash_system_messages
    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "First"),
      TavernKit::Prompt::Block.new(role: :system, content: "Second"),
      TavernKit::Prompt::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    msgs = plan.to_messages(dialect: :openai, squash_system_messages: true)
    assert_equal 2, msgs.size
    assert_equal "First\nSecond", msgs[0][:content]
    assert_equal "Hello!", msgs[1][:content]
  end

  def test_squash_preserves_named_system_blocks
    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "First"),
      TavernKit::Prompt::Block.new(role: :system, content: "Named", name: "narrator"),
      TavernKit::Prompt::Block.new(role: :system, content: "Third"),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    msgs = plan.to_messages(dialect: :openai, squash_system_messages: true)
    assert_equal 3, msgs.size
  end

  def test_greeting
    plan = TavernKit::Prompt::Plan.new(blocks: [], greeting: "Hello, traveler!", greeting_index: 0)
    assert plan.greeting?
    assert_equal "Hello, traveler!", plan.greeting
    assert_equal 0, plan.greeting_index
  end

  def test_warnings
    plan = TavernKit::Prompt::Plan.new(blocks: [], warnings: ["warn1", "warn2"])
    assert_equal ["warn1", "warn2"], plan.warnings
  end

  def test_debug_dump
    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "System prompt", slot: :main_prompt),
      TavernKit::Prompt::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    dump = plan.debug_dump
    assert_includes dump, "[system] (main_prompt)"
    assert_includes dump, "System prompt"
    assert_includes dump, "[user]"
    assert_includes dump, "Hello!"
  end
end
