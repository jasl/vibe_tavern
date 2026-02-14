# frozen_string_literal: true

require "test_helper"

class AgentCore::MessageTest < Minitest::Test
  def test_simple_text_message
    msg = AgentCore::Message.new(role: :user, content: "Hello!")
    assert_equal :user, msg.role
    assert_equal "Hello!", msg.content
    assert_equal "Hello!", msg.text
    assert msg.user?
    refute msg.assistant?
  end

  def test_assistant_message_with_tool_calls
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { path: "foo.txt" })
    msg = AgentCore::Message.new(
      role: :assistant,
      content: "Let me read that.",
      tool_calls: [tc]
    )
    assert msg.assistant?
    assert msg.has_tool_calls?
    assert_equal 1, msg.tool_calls.size
    assert_equal "read", msg.tool_calls.first.name
  end

  def test_tool_result_message
    msg = AgentCore::Message.new(
      role: :tool_result,
      content: "file contents here",
      tool_call_id: "tc_1",
      name: "read"
    )
    assert msg.tool_result?
    assert_equal "tc_1", msg.tool_call_id
  end

  def test_system_message
    msg = AgentCore::Message.new(role: :system, content: "You are helpful.")
    assert msg.system?
  end

  def test_invalid_role_raises
    assert_raises(ArgumentError) do
      AgentCore::Message.new(role: :invalid, content: "x")
    end
  end

  def test_text_with_content_blocks
    blocks = [
      AgentCore::TextContent.new(text: "Hello "),
      AgentCore::TextContent.new(text: "world!"),
    ]
    msg = AgentCore::Message.new(role: :assistant, content: blocks)
    assert_equal "Hello world!", msg.text
  end

  def test_serialization_roundtrip
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { path: "x" })
    msg = AgentCore::Message.new(
      role: :assistant,
      content: "Let me check.",
      tool_calls: [tc],
      metadata: { timestamp: 123 }
    )

    h = msg.to_h
    restored = AgentCore::Message.from_h(h)

    assert_equal msg.role, restored.role
    assert_equal msg.text, restored.text
    assert_equal msg.tool_calls.size, restored.tool_calls.size
    assert_equal "read", restored.tool_calls.first.name
  end

  def test_metadata_is_frozen
    msg = AgentCore::Message.new(role: :user, content: "hi", metadata: { foo: "bar" })
    assert msg.metadata.frozen?
  end

  def test_nil_role_raises_argument_error
    assert_raises(ArgumentError) do
      AgentCore::Message.new(role: nil, content: "x")
    end
  end

  def test_content_is_frozen
    msg = AgentCore::Message.new(role: :user, content: "hello")
    assert msg.content.frozen?
  end

  def test_empty_content_blocks_text
    msg = AgentCore::Message.new(role: :assistant, content: [])
    assert_equal "", msg.text
  end
end

class AgentCore::ToolCallTest < Minitest::Test
  def test_basic_tool_call
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "bash", arguments: { command: "ls" })
    assert_equal "tc_1", tc.id
    assert_equal "bash", tc.name
    assert_equal({ command: "ls" }, tc.arguments)
  end

  def test_serialization_roundtrip
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { path: "a.txt" })
    restored = AgentCore::ToolCall.from_h(tc.to_h)
    assert_equal tc, restored
  end
end

class AgentCore::ContentBlockTest < Minitest::Test
  def test_text_content
    tc = AgentCore::TextContent.new(text: "hello")
    assert_equal :text, tc.type
    assert_equal "hello", tc.text
    assert_equal({ type: :text, text: "hello" }, tc.to_h)
  end

  def test_image_content
    ic = AgentCore::ImageContent.new(source: { type: "base64", data: "abc" }, media_type: "image/png")
    assert_equal :image, ic.type
    assert_equal "image/png", ic.media_type
  end

  def test_from_h_text
    block = AgentCore::ContentBlock.from_h({ type: "text", text: "hi" })
    assert_instance_of AgentCore::TextContent, block
    assert_equal "hi", block.text
  end

  def test_from_h_image
    block = AgentCore::ContentBlock.from_h({ type: "image", source: { url: "http://x" } })
    assert_instance_of AgentCore::ImageContent, block
  end
end
