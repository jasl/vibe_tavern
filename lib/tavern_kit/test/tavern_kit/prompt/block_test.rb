# frozen_string_literal: true

require "test_helper"

class TavernKit::Prompt::BlockTest < Minitest::Test
  def test_basic_block
    block = TavernKit::Prompt::Block.new(role: :system, content: "You are a helpful assistant.")
    assert_equal :system, block.role
    assert_equal "You are a helpful assistant.", block.content
    assert block.enabled?
    assert block.removable?
    refute block.disabled?
    assert_equal :relative, block.insertion_point
    assert block.relative?
    refute block.in_chat?
  end

  def test_block_with_all_attributes
    block = TavernKit::Prompt::Block.new(
      id: "test-001",
      role: :user,
      content: "Hello!",
      name: "Alice",
      attachments: [{ type: "image", url: "https://example.test/image.png" }],
      message_metadata: { tool_call_id: "call_123" },
      slot: :main_prompt,
      enabled: false,
      removable: false,
      insertion_point: :in_chat,
      depth: 2,
      order: 50,
      priority: 10,
      token_budget_group: :system,
      tags: [:core],
      metadata: { source: "test" },
    )

    assert_equal "test-001", block.id
    assert_equal :user, block.role
    assert_equal "Hello!", block.content
    assert_equal "Alice", block.name
    assert_equal [{ type: "image", url: "https://example.test/image.png" }], block.attachments
    assert block.attachments.frozen?
    assert_equal({ tool_call_id: "call_123" }, block.message_metadata)
    assert block.message_metadata.frozen?
    assert_equal :main_prompt, block.slot
    refute block.enabled?
    assert block.disabled?
    refute block.removable?
    assert block.in_chat?
    assert_equal 2, block.depth
    assert_equal 50, block.order
    assert_equal 10, block.priority
    assert_equal :system, block.token_budget_group
    assert_equal [:core], block.tags
    assert_equal({ source: "test" }, block.metadata)
    assert block.metadata.frozen?
  end

  def test_block_auto_generates_id
    block = TavernKit::Prompt::Block.new(role: :system, content: "test")
    refute_nil block.id
    assert_kind_of String, block.id
    assert_match(/\A[0-9a-f-]+\z/, block.id)
  end

  def test_block_to_message
    block = TavernKit::Prompt::Block.new(
      role: :user,
      content: "Hello!",
      name: "Alice",
      attachments: [{ type: "image", url: "https://example.test/image.png" }],
      message_metadata: { tool_call_id: "call_123" },
    )
    msg = block.to_message
    assert_kind_of TavernKit::Prompt::Message, msg
    assert_equal :user, msg.role
    assert_equal "Hello!", msg.content
    assert_equal "Alice", msg.name
    assert_equal [{ type: "image", url: "https://example.test/image.png" }], msg.attachments
    assert_equal({ tool_call_id: "call_123" }, msg.metadata)
  end

  def test_block_to_h
    block = TavernKit::Prompt::Block.new(role: :system, content: "test", id: "x")
    h = block.to_h
    assert_equal "x", h[:id]
    assert_equal :system, h[:role]
    assert_equal "test", h[:content]
  end

  def test_block_with
    block = TavernKit::Prompt::Block.new(role: :system, content: "original", id: "x")
    modified = block.with(content: "modified")
    assert_equal "original", block.content
    assert_equal "modified", modified.content
    assert_equal "x", modified.id
  end

  def test_block_disable_enable
    block = TavernKit::Prompt::Block.new(role: :system, content: "test")
    assert block.enabled?

    disabled = block.disable
    refute disabled.enabled?
    assert disabled.disabled?

    enabled = disabled.enable
    assert enabled.enabled?
  end

  def test_block_invalid_role
    assert_raises(ArgumentError) do
      TavernKit::Prompt::Block.new(role: "system", content: "test")
    end
  end

  def test_block_invalid_content
    assert_raises(ArgumentError) do
      TavernKit::Prompt::Block.new(role: :system, content: 42)
    end
  end

  def test_block_invalid_insertion_point
    assert_raises(ArgumentError) do
      TavernKit::Prompt::Block.new(role: :system, content: "test", insertion_point: "in_chat")
    end
  end

  def test_block_invalid_budget_group
    assert_raises(ArgumentError) do
      TavernKit::Prompt::Block.new(role: :system, content: "test", token_budget_group: "system")
    end
  end

  def test_block_tags_are_frozen
    block = TavernKit::Prompt::Block.new(role: :system, content: "test", tags: [:a, :b])
    assert block.tags.frozen?
  end
end
