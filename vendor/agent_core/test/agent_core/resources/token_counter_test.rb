# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::TokenCounter::HeuristicTest < Minitest::Test
  def setup
    @counter = AgentCore::Resources::TokenCounter::Heuristic.new
  end

  def test_count_text_basic
    # "Hello, world!" = 13 chars → ceil(13/4.0) = 4
    assert_equal 4, @counter.count_text("Hello, world!")
  end

  def test_count_text_non_ascii_defaults_to_one_char_per_token
    # 2 non-ASCII chars → ceil(2/1.0) = 2
    assert_equal 2, @counter.count_text("你好")
  end

  def test_count_text_mixed_ascii_and_non_ascii
    # "Hello你好": 5 ASCII chars → ceil(5/4.0) = 2
    # 2 non-ASCII chars → ceil(2/1.0) = 2
    assert_equal 4, @counter.count_text("Hello你好")
  end

  def test_custom_non_ascii_chars_per_token
    counter = AgentCore::Resources::TokenCounter::Heuristic.new(non_ascii_chars_per_token: 2.0)
    # 2 non-ASCII chars → ceil(2/2.0) = 1
    assert_equal 1, counter.count_text("你好")
  end

  def test_count_text_empty_string
    assert_equal 0, @counter.count_text("")
  end

  def test_count_text_nil
    assert_equal 0, @counter.count_text(nil)
  end

  def test_count_text_exact_boundary
    # 8 chars → ceil(8/4.0) = 2
    assert_equal 2, @counter.count_text("12345678")
  end

  def test_custom_chars_per_token
    counter = AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: 2.0)
    # 10 chars → ceil(10/2.0) = 5
    assert_equal 5, counter.count_text("1234567890")
  end

  def test_invalid_chars_per_token_raises
    assert_raises(ArgumentError) do
      AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: 0)
    end

    assert_raises(ArgumentError) do
      AgentCore::Resources::TokenCounter::Heuristic.new(chars_per_token: -1)
    end
  end

  def test_invalid_non_ascii_chars_per_token_raises
    assert_raises(ArgumentError) do
      AgentCore::Resources::TokenCounter::Heuristic.new(non_ascii_chars_per_token: 0)
    end

    assert_raises(ArgumentError) do
      AgentCore::Resources::TokenCounter::Heuristic.new(non_ascii_chars_per_token: -1)
    end
  end

  def test_count_messages_string_content
    msgs = [
      AgentCore::Message.new(role: :user, content: "Hello!"),       # 6 chars → 2 tokens + 4 overhead = 6
      AgentCore::Message.new(role: :assistant, content: "Hi there!"), # 9 chars → 3 tokens + 4 overhead = 7
    ]
    result = @counter.count_messages(msgs)
    assert_equal 13, result
  end

  def test_count_messages_array_content_with_text_blocks
    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::TextContent.new(text: "Hello!"),       # 6 chars → 2 tokens
        AgentCore::TextContent.new(text: "Hi there!"),    # 9 chars → 3 tokens
      ]),
    ]
    # 2 + 3 text tokens + 4 overhead = 9
    result = @counter.count_messages(msgs)
    assert_equal 9, result
  end

  def test_count_messages_with_image_block
    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::TextContent.new(text: "Look:"),  # 5 chars → 2 tokens
        AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "iVBOR"),
      ]),
    ]
    # 2 text + 1600 image + 4 overhead = 1606
    result = @counter.count_messages(msgs)
    assert_equal 1606, result
  end

  def test_count_messages_with_document_block_binary
    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::DocumentContent.new(source_type: :base64, media_type: "application/pdf", data: "JVBERi"),
      ]),
    ]
    # 2000 document + 4 overhead = 2004
    result = @counter.count_messages(msgs)
    assert_equal 2004, result
  end

  def test_count_messages_with_document_block_text_based
    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::DocumentContent.new(source_type: :base64, media_type: "text/plain", data: "Hello world!"),
      ]),
    ]
    # "Hello world!" = 12 chars → ceil(12/4) = 3 text tokens + 4 overhead = 7
    result = @counter.count_messages(msgs)
    assert_equal 7, result
  end

  def test_count_messages_with_audio_block_with_transcript
    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "UklGR", transcript: "Hello world!"),
      ]),
    ]
    # "Hello world!" = 12 chars → ceil(12/4) = 3 text tokens + 4 overhead = 7
    result = @counter.count_messages(msgs)
    assert_equal 7, result
  end

  def test_count_messages_with_audio_block_without_transcript
    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "UklGR"),
      ]),
    ]
    # 1000 audio + 4 overhead = 1004
    result = @counter.count_messages(msgs)
    assert_equal 1004, result
  end

  def test_count_messages_empty
    assert_equal 0, @counter.count_messages([])
    assert_equal 0, @counter.count_messages(nil)
  end

  def test_count_content_block_dispatches_correctly
    assert_equal 1600, @counter.count_content_block(
      AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "x")
    )
    assert_equal 2000, @counter.count_content_block(
      AgentCore::DocumentContent.new(source_type: :base64, media_type: "application/pdf", data: "x")
    )
    assert_equal 1000, @counter.count_content_block(
      AgentCore::AudioContent.new(source_type: :base64, media_type: "audio/wav", data: "x")
    )
  end

  def test_count_tools
    tools = [
      { name: "read", description: "Read a file", parameters: { type: "object" } },
    ]
    result = @counter.count_tools(tools)
    assert result > 0
  end

  def test_count_tools_empty
    assert_equal 0, @counter.count_tools([])
    assert_equal 0, @counter.count_tools(nil)
  end
end

class AgentCore::Resources::TokenCounter::BaseTest < Minitest::Test
  def test_count_text_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) do
      AgentCore::Resources::TokenCounter::Base.new.count_text("hello")
    end
  end

  def test_count_messages_string_content_delegates_to_count_text
    counter = Class.new(AgentCore::Resources::TokenCounter::Base) do
      def count_text(text)
        text.to_s.length
      end
    end.new

    msgs = [AgentCore::Message.new(role: :user, content: "ab")]
    # "ab" = 2 chars + 4 overhead = 6
    assert_equal 6, counter.count_messages(msgs)
  end

  def test_count_messages_array_content_dispatches_blocks
    counter = Class.new(AgentCore::Resources::TokenCounter::Base) do
      def count_text(text)
        text.to_s.length
      end
    end.new

    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::TextContent.new(text: "hi"),  # 2 chars
        AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "x"),
      ]),
    ]
    # 2 text + 1600 image + 4 overhead = 1606
    assert_equal 1606, counter.count_messages(msgs)
  end

  def test_count_image_can_be_overridden
    counter = Class.new(AgentCore::Resources::TokenCounter::Base) do
      def count_text(text) = text.to_s.length
      def count_image(_block) = 500
    end.new

    msgs = [
      AgentCore::Message.new(role: :user, content: [
        AgentCore::ImageContent.new(source_type: :base64, media_type: "image/png", data: "x"),
      ]),
    ]
    # 500 image + 4 overhead = 504
    assert_equal 504, counter.count_messages(msgs)
  end
end
