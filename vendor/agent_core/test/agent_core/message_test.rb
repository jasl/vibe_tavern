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

  # --- ImageContent ---

  def test_image_content_base64
    ic = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "iVBOR")
    assert_equal :image, ic.type
    assert_equal :base64, ic.source_type
    assert_equal "image/png", ic.media_type
    assert_equal "iVBOR", ic.data
    assert_nil ic.url
  end

  def test_image_content_url
    ic = AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg")
    assert_equal :image, ic.type
    assert_equal :url, ic.source_type
    assert_equal "https://example.com/img.jpg", ic.url
    assert_nil ic.data
  end

  def test_image_content_url_can_be_disabled_by_config
    AgentCore.configure { |c| c.allow_url_media_sources = false }

    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg")
    end
  ensure
    AgentCore.reset_config!
  end

  def test_image_content_url_scheme_can_be_restricted_by_config
    AgentCore.configure do |c|
      c.allowed_media_url_schemes = %w[https]
    end

    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :url, url: "http://example.com/img.jpg")
    end

    ic = AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg")
    assert_equal :url, ic.source_type
  ensure
    AgentCore.reset_config!
  end

  def test_media_source_validator_hook_can_reject
    AgentCore.configure do |c|
      c.media_source_validator = lambda do |block|
        block.source_type != :url
      end
    end

    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg")
    end

    ic = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "iVBOR")
    assert_equal :base64, ic.source_type
  ensure
    AgentCore.reset_config!
  end

  def test_image_content_url_with_media_type
    ic = AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg", media_type: "image/jpeg")
    assert_equal "image/jpeg", ic.media_type
  end

  def test_image_content_effective_media_type_infers_from_url
    ic = AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/photo.jpg")
    assert_equal "image/jpeg", ic.effective_media_type
  end

  def test_image_content_base64_requires_data
    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png")
    end
  end

  def test_image_content_base64_requires_media_type
    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :base64, data: "iVBOR")
    end
  end

  def test_image_content_url_requires_url
    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :url)
    end
  end

  def test_image_content_requires_source_type
    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: nil, data: "x", media_type: "image/png")
    end
  end

  def test_image_content_rejects_invalid_source_type
    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :file, data: "x", media_type: "image/png")
    end
  end

  def test_image_content_serialization_roundtrip_base64
    ic = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "iVBOR")
    h = ic.to_h
    restored = AgentCore::ImageContent.from_h(h)
    assert_equal ic, restored
    assert_equal :base64, restored.source_type
    assert_equal "iVBOR", restored.data
  end

  def test_image_content_serialization_roundtrip_url
    ic = AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg", media_type: "image/jpeg")
    h = ic.to_h
    restored = AgentCore::ImageContent.from_h(h)
    assert_equal ic, restored
    assert_equal :url, restored.source_type
    assert_equal "https://example.com/img.jpg", restored.url
  end

  def test_image_content_equality
    a = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc")
    b = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc")
    c = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "xyz")
    d = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/jpeg", data: "abc")
    assert_equal a, b
    refute_equal a, c
    refute_equal a, d
  end

  def test_image_data_is_frozen
    ic = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc")
    assert ic.data.frozen?
  end

  # --- DocumentContent ---

  def test_document_content_base64_pdf
    dc = AgentCore::DocumentContent.new(
      source_type: :base64, media_type: "application/pdf", data: "JVBERi",
      filename: "report.pdf", title: "Q4 Report"
    )
    assert_equal :document, dc.type
    assert_equal :base64, dc.source_type
    assert_equal "application/pdf", dc.media_type
    assert_equal "JVBERi", dc.data
    assert_equal "report.pdf", dc.filename
    assert_equal "Q4 Report", dc.title
  end

  def test_document_content_url
    dc = AgentCore::DocumentContent.new(
      source_type: :url, url: "https://example.com/doc.pdf", media_type: "application/pdf"
    )
    assert_equal :url, dc.source_type
    assert_equal "https://example.com/doc.pdf", dc.url
  end

  def test_document_content_effective_media_type_infers_from_filename_or_url
    dc = AgentCore::DocumentContent.new(source_type: :url, url: "https://example.com/report.pdf")
    assert_equal "application/pdf", dc.effective_media_type
  end

  def test_document_content_text_based
    dc = AgentCore::DocumentContent.new(
      source_type: :base64, media_type: "text/plain", data: "Hello world"
    )
    assert dc.text_based?
    assert_equal "Hello world", dc.text
  end

  def test_document_content_binary_not_text_based
    dc = AgentCore::DocumentContent.new(
      source_type: :base64, media_type: "application/pdf", data: "JVBERi"
    )
    refute dc.text_based?
    assert_nil dc.text
  end

  def test_document_content_validation
    assert_raises(ArgumentError) { AgentCore::DocumentContent.new(source_type: :base64, data: "x") }
    assert_raises(ArgumentError) { AgentCore::DocumentContent.new(source_type: :url) }
  end

  def test_document_content_serialization_roundtrip
    dc = AgentCore::DocumentContent.new(
      source_type: :base64, media_type: "application/pdf", data: "JVBERi",
      filename: "report.pdf", title: "Q4"
    )
    h = dc.to_h
    restored = AgentCore::DocumentContent.from_h(h)
    assert_equal dc, restored
    assert_equal "report.pdf", restored.filename
    assert_equal "Q4", restored.title
  end

  # --- AudioContent ---

  def test_audio_content_base64_with_transcript
    ac = AgentCore::AudioContent.new(
      source_type: :base64, media_type: "audio/wav", data: "UklGR",
      transcript: "Hello world"
    )
    assert_equal :audio, ac.type
    assert_equal :base64, ac.source_type
    assert_equal "audio/wav", ac.media_type
    assert_equal "UklGR", ac.data
    assert_equal "Hello world", ac.transcript
    assert_equal "Hello world", ac.text
  end

  def test_audio_content_without_transcript
    ac = AgentCore::AudioContent.new(
      source_type: :base64, media_type: "audio/wav", data: "UklGR"
    )
    assert_nil ac.text
  end

  def test_audio_content_url
    ac = AgentCore::AudioContent.new(
      source_type: :url, url: "https://example.com/audio.mp3"
    )
    assert_equal :url, ac.source_type
    assert_equal "https://example.com/audio.mp3", ac.url
  end

  def test_audio_content_effective_media_type_infers_from_url
    ac = AgentCore::AudioContent.new(source_type: :url, url: "https://example.com/audio.mp3")
    assert_equal "audio/mpeg", ac.effective_media_type
  end

  def test_audio_content_validation
    assert_raises(ArgumentError) { AgentCore::AudioContent.new(source_type: :base64, data: "x") }
    assert_raises(ArgumentError) { AgentCore::AudioContent.new(source_type: :url) }
  end

  def test_audio_content_serialization_roundtrip
    ac = AgentCore::AudioContent.new(
      source_type: :base64, media_type: "audio/wav", data: "UklGR",
      transcript: "Hello"
    )
    h = ac.to_h
    restored = AgentCore::AudioContent.from_h(h)
    assert_equal ac, restored
    assert_equal "Hello", restored.transcript
  end

  def test_audio_content_equality
    a = AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "UklGR", transcript: "Hello")
    b = AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "UklGR", transcript: "Hello")
    c = AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "UklGR", transcript: "World")
    d = AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/mp3", data: "UklGR", transcript: "Hello")
    assert_equal a, b
    refute_equal a, c
    refute_equal a, d
  end

  # --- ContentBlock.from_h dispatch ---

  def test_from_h_text
    block = AgentCore::ContentBlock.from_h({ type: "text", text: "hi" })
    assert_instance_of AgentCore::TextContent, block
    assert_equal "hi", block.text
  end

  def test_from_h_image
    block = AgentCore::ContentBlock.from_h({
      type: "image", source_type: "base64", data: "abc", media_type: "image/png",
    })
    assert_instance_of AgentCore::ImageContent, block
    assert_equal :base64, block.source_type
  end

  def test_from_h_document
    block = AgentCore::ContentBlock.from_h({
      type: "document", source_type: "base64", data: "JVBERi", media_type: "application/pdf",
    })
    assert_instance_of AgentCore::DocumentContent, block
    assert_equal :base64, block.source_type
  end

  def test_from_h_audio
    block = AgentCore::ContentBlock.from_h({
      type: "audio", source_type: "base64", data: "UklGR", media_type: "audio/wav",
      transcript: "Hello",
    })
    assert_instance_of AgentCore::AudioContent, block
    assert_equal "Hello", block.transcript
  end

  def test_from_h_unknown_falls_back_to_text
    block = AgentCore::ContentBlock.from_h({ type: "unknown", text: "fallback" })
    assert_instance_of AgentCore::TextContent, block
    assert_equal "fallback", block.text
  end

  # --- Message with multimodal content ---

  def test_message_with_mixed_content_blocks
    blocks = [
      AgentCore::TextContent.new(text: "Here's the image: "),
      AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "iVBOR"),
    ]
    msg = AgentCore::Message.new(role: :user, content: blocks)
    assert_equal "Here's the image: ", msg.text
    assert_equal 2, msg.content.size
  end

  def test_message_serialization_with_multimodal_content
    blocks = [
      AgentCore::TextContent.new(text: "Look at this"),
      AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc"),
      AgentCore::DocumentContent.new(source_type: :base64, media_type: "application/pdf", data: "JVBERi"),
    ]
    msg = AgentCore::Message.new(role: :user, content: blocks)
    h = msg.to_h

    restored = AgentCore::Message.from_h(h)
    assert_equal 3, restored.content.size
    assert_instance_of AgentCore::TextContent, restored.content[0]
    assert_instance_of AgentCore::ImageContent, restored.content[1]
    assert_instance_of AgentCore::DocumentContent, restored.content[2]
  end
end
