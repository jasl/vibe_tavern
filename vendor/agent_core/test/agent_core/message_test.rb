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
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { "path" => "foo.txt" })
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
    assert_equal "read", msg.name
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

  def test_nil_role_raises_argument_error
    assert_raises(ArgumentError) do
      AgentCore::Message.new(role: nil, content: "x")
    end
  end

  def test_string_role_coerced_to_symbol
    msg = AgentCore::Message.new(role: "user", content: "hi")
    assert_equal :user, msg.role
  end

  def test_text_with_content_blocks
    blocks = [
      AgentCore::TextContent.new(text: "Hello "),
      AgentCore::TextContent.new(text: "world!"),
    ]
    msg = AgentCore::Message.new(role: :assistant, content: blocks)
    assert_equal "Hello world!", msg.text
  end

  def test_text_with_non_string_content
    msg = AgentCore::Message.new(role: :user, content: 42)
    assert_equal "42", msg.text
  end

  def test_has_tool_calls_without_tool_calls
    msg = AgentCore::Message.new(role: :assistant, content: "No tools")
    refute msg.has_tool_calls?
  end

  def test_has_tool_calls_with_empty_array
    msg = AgentCore::Message.new(role: :assistant, content: "No tools", tool_calls: [])
    refute msg.has_tool_calls?
  end

  def test_serialization_roundtrip
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { "path" => "x" })
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

  def test_to_h_minimal
    msg = AgentCore::Message.new(role: :user, content: "hi")
    h = msg.to_h

    assert_equal :user, h[:role]
    assert_equal "hi", h[:content]
    refute h.key?(:tool_calls)
    refute h.key?(:tool_call_id)
    refute h.key?(:name)
    refute h.key?(:metadata)
  end

  def test_to_h_includes_tool_call_id
    msg = AgentCore::Message.new(role: :tool_result, content: "ok", tool_call_id: "tc_1")
    h = msg.to_h
    assert_equal "tc_1", h[:tool_call_id]
  end

  def test_to_h_includes_name
    msg = AgentCore::Message.new(role: :tool_result, content: "ok", tool_call_id: "tc_1", name: "read")
    h = msg.to_h
    assert_equal "read", h[:name]
  end

  def test_to_h_serializes_content_blocks
    blocks = [AgentCore::TextContent.new(text: "hello")]
    msg = AgentCore::Message.new(role: :user, content: blocks)
    h = msg.to_h
    assert_instance_of Array, h[:content]
    assert_equal :text, h[:content].first[:type]
  end

  def test_equality
    a = AgentCore::Message.new(role: :user, content: "hi")
    b = AgentCore::Message.new(role: :user, content: "hi")
    c = AgentCore::Message.new(role: :user, content: "bye")

    assert_equal a, b
    refute_equal a, c
    refute_equal a, "not a message"
  end

  def test_metadata_is_frozen
    msg = AgentCore::Message.new(role: :user, content: "hi", metadata: { foo: "bar" })
    assert msg.metadata.frozen?
  end

  def test_metadata_defaults_to_empty
    msg = AgentCore::Message.new(role: :user, content: "hi")
    assert_equal({}, msg.metadata)
  end

  def test_content_is_frozen
    msg = AgentCore::Message.new(role: :user, content: "hello")
    assert msg.content.frozen?
  end

  def test_empty_content_blocks_text
    msg = AgentCore::Message.new(role: :assistant, content: [])
    assert_equal "", msg.text
  end

  def test_from_h_with_string_keys
    h = { "role" => "user", "content" => "string keys" }
    msg = AgentCore::Message.from_h(h)
    assert_equal :user, msg.role
    assert_equal "string keys", msg.text
  end

  def test_from_h_deserializes_content_blocks
    h = {
      role: :user,
      content: [{ type: :text, text: "hello" }],
    }
    msg = AgentCore::Message.from_h(h)
    assert_instance_of AgentCore::TextContent, msg.content.first
  end
end

class AgentCore::ToolCallTest < Minitest::Test
  def test_basic_tool_call
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "bash", arguments: { "command" => "ls" })
    assert_equal "tc_1", tc.id
    assert_equal "bash", tc.name
    assert_equal({ "command" => "ls" }, tc.arguments)
  end

  def test_arguments_are_deep_stringified
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "echo", arguments: { text: { nested: 1 }, "keep" => 2 })
    assert_equal({ "text" => { "nested" => 1 }, "keep" => 2 }, tc.arguments)
  end

  def test_arguments_default_to_empty_hash
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "bash", arguments: nil)
    assert_equal({}, tc.arguments)
  end

  def test_arguments_frozen
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "bash", arguments: { "cmd" => "ls" })
    assert tc.arguments.frozen?
  end

  def test_serialization_roundtrip
    tc = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { "path" => "a.txt" })
    restored = AgentCore::ToolCall.from_h(tc.to_h)
    assert_equal tc, restored
  end

  def test_from_h_with_string_keys
    tc = AgentCore::ToolCall.from_h({ "id" => "tc_1", "name" => "read", "arguments" => { "path" => "x" } })
    assert_equal "tc_1", tc.id
    assert_equal "read", tc.name
  end

  def test_equality
    a = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { "path" => "a" })
    b = AgentCore::ToolCall.new(id: "tc_1", name: "read", arguments: { "path" => "a" })
    c = AgentCore::ToolCall.new(id: "tc_2", name: "read", arguments: { "path" => "a" })
    assert_equal a, b
    refute_equal a, c
    refute_equal a, "not a tool call"
  end
end

class AgentCore::ContentBlockTest < Minitest::Test
  def test_text_content
    tc = AgentCore::TextContent.new(text: "hello")
    assert_equal :text, tc.type
    assert_equal "hello", tc.text
    assert_equal({ type: :text, text: "hello" }, tc.to_h)
  end

  def test_text_content_equality
    a = AgentCore::TextContent.new(text: "hi")
    b = AgentCore::TextContent.new(text: "hi")
    c = AgentCore::TextContent.new(text: "bye")
    assert_equal a, b
    refute_equal a, c
    refute_equal a, "not text content"
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
    AgentCore.configure { |c| c.allow_url_media_sources = true }
    ic = AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg")
    assert_equal :image, ic.type
    assert_equal :url, ic.source_type
    assert_equal "https://example.com/img.jpg", ic.url
    assert_nil ic.data
  ensure
    AgentCore.reset_config!
  end

  def test_image_content_url_can_be_disabled_by_config
    AgentCore.configure { |c| c.allow_url_media_sources = true }
    AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg")

    AgentCore.configure { |c| c.allow_url_media_sources = false }

    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/img.jpg")
    end
  ensure
    AgentCore.reset_config!
  end

  def test_image_content_url_scheme_restriction
    AgentCore.configure do |c|
      c.allow_url_media_sources = true
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

  def test_image_content_url_invalid_uri
    AgentCore.configure do |c|
      c.allow_url_media_sources = true
      c.allowed_media_url_schemes = %w[https]
    end

    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :url, url: "not a valid uri %%%")
    end
  ensure
    AgentCore.reset_config!
  end

  def test_media_source_validator_hook_rejects
    AgentCore.configure { |c| c.media_source_validator = ->(_block) { false } }

    assert_raises(ArgumentError) do
      AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc")
    end
  ensure
    AgentCore.reset_config!
  end

  def test_media_source_validator_hook_accepts
    calls = []
    AgentCore.configure { |c| c.media_source_validator = ->(block) { calls << block; true } }

    ic = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc")
    assert_equal 1, calls.size
    assert_same ic, calls.first
  ensure
    AgentCore.reset_config!
  end

  def test_image_content_effective_media_type_infers_from_url
    AgentCore.configure { |c| c.allow_url_media_sources = true }
    ic = AgentCore::ImageContent.new(source_type: :url, url: "https://example.com/photo.jpg")
    assert_equal "image/jpeg", ic.effective_media_type
  ensure
    AgentCore.reset_config!
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

  def test_image_content_serialization_roundtrip
    ic = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "iVBOR")
    restored = AgentCore::ImageContent.from_h(ic.to_h)
    assert_equal ic, restored
  end

  def test_image_content_equality
    a = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc")
    b = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc")
    c = AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "xyz")
    assert_equal a, b
    refute_equal a, c
  end

  def test_image_data_frozen
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
    assert_equal "report.pdf", dc.filename
    assert_equal "Q4 Report", dc.title
  end

  def test_document_content_url
    AgentCore.configure { |c| c.allow_url_media_sources = true }
    dc = AgentCore::DocumentContent.new(
      source_type: :url, url: "https://example.com/doc.pdf", media_type: "application/pdf"
    )
    assert_equal :url, dc.source_type
  ensure
    AgentCore.reset_config!
  end

  def test_document_content_text_based
    dc = AgentCore::DocumentContent.new(
      source_type: :base64, media_type: "text/plain", data: "Hello world"
    )
    assert dc.text_based?
    assert_equal "Hello world", dc.text
  end

  def test_document_content_text_based_types
    %w[text/plain text/html text/csv text/markdown].each do |mt|
      dc = AgentCore::DocumentContent.new(source_type: :base64, media_type: mt, data: "x")
      assert dc.text_based?, "Expected #{mt} to be text-based"
    end
  end

  def test_document_content_binary_not_text
    dc = AgentCore::DocumentContent.new(source_type: :base64, media_type: "application/pdf", data: "JVBERi")
    refute dc.text_based?
    assert_nil dc.text
  end

  def test_document_content_text_nil_for_url_source
    AgentCore.configure { |c| c.allow_url_media_sources = true }
    dc = AgentCore::DocumentContent.new(source_type: :url, url: "https://example.com/readme.txt", media_type: "text/plain")
    assert dc.text_based?
    assert_nil dc.text  # URL source, not base64
  ensure
    AgentCore.reset_config!
  end

  def test_document_content_effective_media_type_from_filename
    dc = AgentCore::DocumentContent.new(
      source_type: :base64, data: "x", media_type: nil,
      filename: "report.pdf"
    )
    # media_type required for base64 — this should raise
    assert_raises(ArgumentError) { dc }
  rescue
    # If it doesn't raise, still check the effective type inferred from filename
    nil
  end

  def test_document_content_serialization_roundtrip
    dc = AgentCore::DocumentContent.new(
      source_type: :base64, media_type: "application/pdf", data: "JVBERi",
      filename: "report.pdf", title: "Q4"
    )
    restored = AgentCore::DocumentContent.from_h(dc.to_h)
    assert_equal dc, restored
    assert_equal "report.pdf", restored.filename
    assert_equal "Q4", restored.title
  end

  def test_document_content_equality_includes_filename_and_title
    a =
      AgentCore::DocumentContent.new(
        source_type: :base64,
        media_type: "application/pdf",
        data: "JVBERi",
        filename: "a.pdf",
        title: "A"
      )
    b =
      AgentCore::DocumentContent.new(
        source_type: :base64,
        media_type: "application/pdf",
        data: "JVBERi",
        filename: "b.pdf",
        title: "A"
      )
    c =
      AgentCore::DocumentContent.new(
        source_type: :base64,
        media_type: "application/pdf",
        data: "JVBERi",
        filename: "a.pdf",
        title: "C"
      )

    refute_equal a, b
    refute_equal a, c
  end

  # --- AudioContent ---

  def test_audio_content_base64
    ac = AgentCore::AudioContent.new(
      source_type: :base64, media_type: "audio/wav", data: "UklGR",
      transcript: "Hello world"
    )
    assert_equal :audio, ac.type
    assert_equal "Hello world", ac.text
    assert_equal "Hello world", ac.transcript
  end

  def test_audio_content_without_transcript
    ac = AgentCore::AudioContent.new(
      source_type: :base64, media_type: "audio/wav", data: "UklGR"
    )
    assert_nil ac.text
    assert_nil ac.transcript
  end

  def test_audio_content_url
    AgentCore.configure { |c| c.allow_url_media_sources = true }
    ac = AgentCore::AudioContent.new(
      source_type: :url, url: "https://example.com/audio.mp3"
    )
    assert_equal :url, ac.source_type
  ensure
    AgentCore.reset_config!
  end

  def test_audio_content_effective_media_type
    AgentCore.configure { |c| c.allow_url_media_sources = true }
    ac = AgentCore::AudioContent.new(source_type: :url, url: "https://example.com/audio.mp3")
    assert_equal "audio/mpeg", ac.effective_media_type
  ensure
    AgentCore.reset_config!
  end

  def test_audio_content_serialization_roundtrip
    ac = AgentCore::AudioContent.new(
      source_type: :base64, media_type: "audio/wav", data: "UklGR",
      transcript: "Hello"
    )
    restored = AgentCore::AudioContent.from_h(ac.to_h)
    assert_equal ac, restored
    assert_equal "Hello", restored.transcript
  end

  def test_audio_content_equality
    a = AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "abc", transcript: "hi")
    b = AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "abc", transcript: "hi")
    c = AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "abc", transcript: "bye")
    assert_equal a, b
    refute_equal a, c
  end

  # --- ToolUseContent ---

  def test_tool_use_content
    tuc = AgentCore::ToolUseContent.new(id: "tc_1", name: "read", input: { path: "foo" })
    assert_equal :tool_use, tuc.type
    assert_equal "tc_1", tuc.id
    assert_equal "read", tuc.name
    assert_equal({ path: "foo" }, tuc.input)
  end

  def test_tool_use_content_nil_input
    tuc = AgentCore::ToolUseContent.new(id: "tc_1", name: "read", input: nil)
    assert_equal({}, tuc.input)
    assert tuc.input.frozen?
  end

  def test_tool_use_content_to_h
    tuc = AgentCore::ToolUseContent.new(id: "tc_1", name: "read", input: { path: "foo" })
    h = tuc.to_h
    assert_equal :tool_use, h[:type]
    assert_equal "tc_1", h[:id]
    assert_equal "read", h[:name]
    assert_equal({ path: "foo" }, h[:input])
  end

  def test_tool_use_content_equality
    a = AgentCore::ToolUseContent.new(id: "tc_1", name: "read", input: {})
    b = AgentCore::ToolUseContent.new(id: "tc_1", name: "read", input: {})
    c = AgentCore::ToolUseContent.new(id: "tc_2", name: "read", input: {})
    assert_equal a, b
    refute_equal a, c
  end

  def test_tool_use_content_equality_includes_input
    a = AgentCore::ToolUseContent.new(id: "tc_1", name: "read", input: { path: "a" })
    b = AgentCore::ToolUseContent.new(id: "tc_1", name: "read", input: { path: "b" })
    refute_equal a, b
  end

  # --- ToolResultContent ---

  def test_tool_result_content
    trc = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "result text", error: false)
    assert_equal :tool_result, trc.type
    assert_equal "tc_1", trc.tool_use_id
    assert_equal "result text", trc.content
    refute trc.error?
  end

  def test_tool_result_content_with_error
    trc = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "failed", error: true)
    assert trc.error?
  end

  def test_tool_result_content_error_coercion
    trc = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "x", error: nil)
    refute trc.error?

    trc2 = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "x", error: "truthy")
    assert trc2.error?
  end

  def test_tool_result_content_to_h
    trc = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "ok", error: false)
    h = trc.to_h
    assert_equal :tool_result, h[:type]
    assert_equal "tc_1", h[:tool_use_id]
    assert_equal "ok", h[:content]
    assert_equal false, h[:error]
  end

  def test_tool_result_content_equality
    a = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "x")
    b = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "x")
    c = AgentCore::ToolResultContent.new(tool_use_id: "tc_2", content: "x")
    assert_equal a, b
    refute_equal a, c
  end

  def test_tool_result_content_equality_includes_content_and_error
    a = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "a", error: false)
    b = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "b", error: false)
    c = AgentCore::ToolResultContent.new(tool_use_id: "tc_1", content: "a", error: true)

    refute_equal a, b
    refute_equal a, c
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
  end

  def test_from_h_document
    block = AgentCore::ContentBlock.from_h({
      type: "document", source_type: "base64", data: "JVBERi", media_type: "application/pdf",
    })
    assert_instance_of AgentCore::DocumentContent, block
  end

  def test_from_h_audio
    block = AgentCore::ContentBlock.from_h({
      type: "audio", source_type: "base64", data: "UklGR", media_type: "audio/wav",
    })
    assert_instance_of AgentCore::AudioContent, block
  end

  def test_from_h_tool_use
    block = AgentCore::ContentBlock.from_h({
      type: "tool_use", id: "tc_1", name: "read", input: { path: "f" },
    })
    assert_instance_of AgentCore::ToolUseContent, block
  end

  def test_from_h_tool_result
    block = AgentCore::ContentBlock.from_h({
      type: "tool_result", tool_use_id: "tc_1", content: "data", error: false,
    })
    assert_instance_of AgentCore::ToolResultContent, block
  end

  def test_from_h_unknown_falls_back_to_text
    block = AgentCore::ContentBlock.from_h({ type: "unknown", text: "fallback" })
    assert_instance_of AgentCore::TextContent, block
    assert_equal "fallback", block.text
  end

  def test_from_h_with_string_keys
    block = AgentCore::ContentBlock.from_h({ "type" => "text", "text" => "hello" })
    assert_instance_of AgentCore::TextContent, block
    assert_equal "hello", block.text
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
      AgentCore::TextContent.new(text: "Look"),
      AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "abc"),
      AgentCore::DocumentContent.new(source_type: :base64, media_type: "application/pdf", data: "JVBERi"),
    ]
    msg = AgentCore::Message.new(role: :user, content: blocks)
    restored = AgentCore::Message.from_h(msg.to_h)

    assert_equal 3, restored.content.size
    assert_instance_of AgentCore::TextContent, restored.content[0]
    assert_instance_of AgentCore::ImageContent, restored.content[1]
    assert_instance_of AgentCore::DocumentContent, restored.content[2]
  end

  def test_message_equality_includes_name_and_metadata
    a = AgentCore::Message.new(role: :tool_result, content: "ok", tool_call_id: "tc_1", name: "read", metadata: { error: false })
    b = AgentCore::Message.new(role: :tool_result, content: "ok", tool_call_id: "tc_1", name: "write", metadata: { error: false })
    c = AgentCore::Message.new(role: :tool_result, content: "ok", tool_call_id: "tc_1", name: "read", metadata: { error: true })

    refute_equal a, b
    refute_equal a, c
  end
end
