# frozen_string_literal: true

require "test_helper"

class TavernKit::PromptBuilder::MessageTest < Minitest::Test
  def test_basic_message
    msg = TavernKit::PromptBuilder::Message.new(role: :user, content: "Hello!")
    assert_equal :user, msg.role
    assert_equal "Hello!", msg.content
    assert_nil msg.name
  end

  def test_message_with_name
    msg = TavernKit::PromptBuilder::Message.new(role: :assistant, content: "Hi!", name: "Bot")
    assert_equal "Bot", msg.name
  end

  def test_message_is_immutable
    msg = TavernKit::PromptBuilder::Message.new(role: :system, content: "test")
    assert msg.frozen?
  end

  def test_message_to_h
    msg = TavernKit::PromptBuilder::Message.new(role: :user, content: "Hello!")
    h = msg.to_h
    assert_equal :user, h[:role]
    assert_equal "Hello!", h[:content]
    refute h.key?(:name)
  end

  def test_message_to_h_with_name
    msg = TavernKit::PromptBuilder::Message.new(role: :user, content: "Hello!", name: "Alice")
    h = msg.to_h
    assert_equal "Alice", h[:name]
  end

  def test_message_invalid_role
    assert_raises(ArgumentError) do
      TavernKit::PromptBuilder::Message.new(role: "user", content: "test")
    end
  end

  def test_message_invalid_content
    assert_raises(ArgumentError) do
      TavernKit::PromptBuilder::Message.new(role: :user, content: 42)
    end
  end

  def test_message_with_swipes
    msg = TavernKit::PromptBuilder::Message.new(role: :assistant, content: "Hi!", swipes: ["Hi!", "Hello!"], swipe_id: 0)
    assert_equal ["Hi!", "Hello!"], msg.swipes
    assert_equal 0, msg.swipe_id
  end

  def test_message_serializable_hash
    msg = TavernKit::PromptBuilder::Message.new(role: :user, content: "Hello!", name: "Alice")
    h = msg.to_serializable_hash
    assert_equal "user", h[:role]
    assert_equal "Hello!", h[:content]
    assert_equal "Alice", h[:name]
  end

  def test_message_serializable_hash_includes_attachments_and_metadata
    msg = TavernKit::PromptBuilder::Message.new(
      role: :user,
      content: "Hello!",
      attachments: [{ type: "image", url: "https://example.test/a.png" }],
      metadata: { provider: "test" },
    )

    h = msg.to_serializable_hash
    assert_equal [{ type: "image", url: "https://example.test/a.png" }], h[:attachments]
    assert_equal({ provider: "test" }, h[:metadata])
  end
end
