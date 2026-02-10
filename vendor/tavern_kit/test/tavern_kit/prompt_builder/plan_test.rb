# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::PlanTest < Minitest::Test
  def test_empty_plan
    plan = TavernKit::PromptBuilder::Plan.new(blocks: [])
    assert_equal 0, plan.size
    assert_equal 0, plan.enabled_size
    assert_equal [], plan.messages
    assert_equal [], plan.warnings
    refute plan.greeting?
    assert plan.frozen?
  end

  def test_plan_with_blocks
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "System prompt"),
      TavernKit::PromptBuilder::Block.new(role: :user, content: "Hello!"),
      TavernKit::PromptBuilder::Block.new(role: :assistant, content: "Hi there!"),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    assert_equal 3, plan.size
    assert_equal 3, plan.enabled_size
    assert_equal 3, plan.messages.size
  end

  def test_enabled_blocks_filters_disabled
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "Active"),
      TavernKit::PromptBuilder::Block.new(role: :system, content: "Disabled", enabled: false),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    assert_equal 2, plan.size
    assert_equal 1, plan.enabled_size
    assert_equal "Active", plan.enabled_blocks.first.content
  end

  def test_to_messages_openai_format
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "System prompt"),
      TavernKit::PromptBuilder::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    msgs = plan.to_messages(dialect: :openai)
    assert_kind_of Array, msgs
    assert_equal 2, msgs.size
    assert_equal "system", msgs[0][:role]
    assert_equal "Hello!", msgs[1][:content]
  end

  def test_squash_system_messages
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "First"),
      TavernKit::PromptBuilder::Block.new(role: :system, content: "Second"),
      TavernKit::PromptBuilder::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    msgs = plan.to_messages(dialect: :openai, squash_system_messages: true)
    assert_equal 2, msgs.size
    assert_equal "First\nSecond", msgs[0][:content]
    assert_equal "Hello!", msgs[1][:content]
  end

  def test_squash_preserves_named_system_blocks
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "First"),
      TavernKit::PromptBuilder::Block.new(role: :system, content: "Named", name: "narrator"),
      TavernKit::PromptBuilder::Block.new(role: :system, content: "Third"),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    msgs = plan.to_messages(dialect: :openai, squash_system_messages: true)
    assert_equal 3, msgs.size
  end

  def test_squash_does_not_merge_system_blocks_with_message_metadata
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "First", message_metadata: { cache_control: "ephemeral" }),
      TavernKit::PromptBuilder::Block.new(role: :system, content: "Second"),
      TavernKit::PromptBuilder::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    msgs = plan.to_messages(dialect: :openai, squash_system_messages: true)
    assert_equal 3, msgs.size
    assert_equal "First", msgs[0][:content]
    assert_equal "Second", msgs[1][:content]
  end

  def test_messages_does_not_merge_in_chat_blocks_with_message_metadata
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :user, content: "First", insertion_point: :in_chat, depth: 1, order: 10),
      TavernKit::PromptBuilder::Block.new(
        role: :user,
        content: "Second",
        insertion_point: :in_chat,
        depth: 1,
        order: 10,
        message_metadata: { tool_call_id: "call_123" },
      ),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    msgs = plan.messages
    assert_equal 2, msgs.size
    assert_equal "First", msgs[0].content
    assert_equal "Second", msgs[1].content
  end

  def test_greeting
    plan = TavernKit::PromptBuilder::Plan.new(blocks: [], greeting: "Hello, traveler!", greeting_index: 0)
    assert plan.greeting?
    assert_equal "Hello, traveler!", plan.greeting
    assert_equal 0, plan.greeting_index
  end

  def test_warnings
    plan = TavernKit::PromptBuilder::Plan.new(blocks: [], warnings: ["warn1", "warn2"])
    assert_equal ["warn1", "warn2"], plan.warnings
  end

  def test_trace
    trace = TavernKit::PromptBuilder::Trace.new(
      steps: [],
      fingerprint: "fp",
      started_at: Time.now,
      finished_at: Time.now,
      total_warnings: [],
    )

    plan = TavernKit::PromptBuilder::Plan.new(blocks: [], trace: trace)
    assert_equal trace, plan.trace
  end

  def test_fingerprint_is_stable_and_sensitive_to_output_shape
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "First"),
      TavernKit::PromptBuilder::Block.new(role: :system, content: "Second"),
      TavernKit::PromptBuilder::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    fp = plan.fingerprint(dialect: :openai, squash_system_messages: false)
    assert_match(/\A[0-9a-f]{64}\z/, fp)
    assert_equal fp, plan.fingerprint(dialect: :openai, squash_system_messages: false)

    squashed = plan.fingerprint(dialect: :openai, squash_system_messages: true)
    refute_equal fp, squashed
  end

  def test_debug_dump
    blocks = [
      TavernKit::PromptBuilder::Block.new(role: :system, content: "System prompt", slot: :main_prompt),
      TavernKit::PromptBuilder::Block.new(role: :user, content: "Hello!"),
    ]
    plan = TavernKit::PromptBuilder::Plan.new(blocks: blocks)

    dump = plan.debug_dump
    assert_includes dump, "[system] (main_prompt)"
    assert_includes dump, "System prompt"
    assert_includes dump, "[user]"
    assert_includes dump, "Hello!"
  end
end
