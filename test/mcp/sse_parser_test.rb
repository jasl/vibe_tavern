# frozen_string_literal: true

require_relative "test_helper"

class MCPSseParserTest < Minitest::Test
  def test_parses_basic_event
    parser = TavernKit::VibeTavern::Tools::MCP::SseParser.new

    events = []
    parser.feed("id: 1\nevent: message\ndata: hello\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "1", events.first.fetch(:id)
    assert_equal "message", events.first.fetch(:event)
    assert_equal "hello", events.first.fetch(:data)
    assert_nil events.first.fetch(:retry_ms)
  end

  def test_multiline_data_and_comments_and_crlf
    parser = TavernKit::VibeTavern::Tools::MCP::SseParser.new

    events = []
    parser.feed(": comment\r\nid: a\r\ndata: one\r\ndata: two\r\n\r\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "a", events.first.fetch(:id)
    assert_equal "one\ntwo", events.first.fetch(:data)
  end

  def test_retry_parses_integer
    parser = TavernKit::VibeTavern::Tools::MCP::SseParser.new

    events = []
    parser.feed("retry: 123\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal 123, events.first.fetch(:retry_ms)
  end

  def test_finish_flushes_last_event_without_newline
    parser = TavernKit::VibeTavern::Tools::MCP::SseParser.new

    events = []
    parser.feed("data: hi") { |e| events << e }
    parser.finish { |e| events << e }

    assert_equal 1, events.size
    assert_equal "hi", events.first.fetch(:data)
  end

  def test_buffer_limit_raises
    parser = TavernKit::VibeTavern::Tools::MCP::SseParser.new(max_buffer_bytes: 5)

    assert_raises(ArgumentError) do
      parser.feed("0123456789")
    end
  end

  def test_event_data_limit_counts_join_newlines
    parser = TavernKit::VibeTavern::Tools::MCP::SseParser.new(max_event_data_bytes: 3)

    events = []
    parser.feed("data: a\ndata: b\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "a\nb", events.first.fetch(:data)
  end

  def test_event_data_limit_raises_when_exceeded
    parser = TavernKit::VibeTavern::Tools::MCP::SseParser.new(max_event_data_bytes: 2)

    assert_raises(TavernKit::VibeTavern::Tools::MCP::SseParser::EventDataTooLargeError) do
      parser.feed("data: a\ndata: b\n\n")
    end
  end
end
