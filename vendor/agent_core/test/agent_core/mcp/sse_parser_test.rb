# frozen_string_literal: true

require "test_helper"

class AgentCore::MCP::SseParserTest < Minitest::Test
  def setup
    @parser = AgentCore::MCP::SseParser.new
  end

  def test_simple_event
    events = []
    @parser.feed("data: hello\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "hello", events[0][:data]
    assert_nil events[0][:id]
    assert_nil events[0][:event]
    assert_nil events[0][:retry_ms]
  end

  def test_multiline_data
    events = []
    @parser.feed("data: line1\ndata: line2\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "line1\nline2", events[0][:data]
  end

  def test_event_with_id_and_type
    events = []
    @parser.feed("id: 42\nevent: message\ndata: payload\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "42", events[0][:id]
    assert_equal "message", events[0][:event]
    assert_equal "payload", events[0][:data]
  end

  def test_retry_field
    events = []
    @parser.feed("retry: 3000\ndata: x\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal 3000, events[0][:retry_ms]
  end

  def test_retry_invalid_ignored
    events = []
    @parser.feed("retry: notanumber\ndata: x\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_nil events[0][:retry_ms]
  end

  def test_retry_negative_ignored
    events = []
    @parser.feed("retry: -1\ndata: x\n\n") { |e| events << e }

    assert_nil events[0][:retry_ms]
  end

  def test_comment_lines_ignored
    events = []
    @parser.feed(": this is a comment\ndata: hello\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "hello", events[0][:data]
  end

  def test_empty_data_field
    events = []
    @parser.feed("data:\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "", events[0][:data]
  end

  def test_multiple_events
    events = []
    @parser.feed("data: first\n\ndata: second\n\n") { |e| events << e }

    assert_equal 2, events.size
    assert_equal "first", events[0][:data]
    assert_equal "second", events[1][:data]
  end

  def test_chunked_input
    events = []
    @parser.feed("da") { |e| events << e }
    @parser.feed("ta: hel") { |e| events << e }
    @parser.feed("lo\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "hello", events[0][:data]
  end

  def test_crlf_line_endings
    events = []
    @parser.feed("data: hello\r\n\r\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "hello", events[0][:data]
  end

  def test_finish_flushes_incomplete_event
    events = []
    @parser.feed("data: trailing") { |e| events << e }
    assert_empty events

    @parser.finish { |e| events << e }
    assert_equal 1, events.size
    assert_equal "trailing", events[0][:data]
  end

  def test_finish_with_empty_buffer
    events = []
    @parser.finish { |e| events << e }
    assert_empty events
  end

  def test_no_data_lines_still_emits_event_with_id
    events = []
    @parser.feed("id: 99\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "99", events[0][:id]
    assert_equal "", events[0][:data]
  end

  def test_data_with_colon_in_value
    events = []
    @parser.feed("data: key: value\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "key: value", events[0][:data]
  end

  def test_field_without_colon
    events = []
    @parser.feed("data\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal "", events[0][:data]
  end

  def test_max_buffer_bytes_enforced
    parser = AgentCore::MCP::SseParser.new(max_buffer_bytes: 10)

    assert_raises(ArgumentError) do
      parser.feed("data: this is way too long\n\n")
    end
  end

  def test_max_event_data_bytes_enforced
    parser = AgentCore::MCP::SseParser.new(max_event_data_bytes: 5)

    assert_raises(AgentCore::MCP::SseParser::EventDataTooLargeError) do
      parser.feed("data: toolong\n\n")
    end
  end

  def test_max_event_data_bytes_multiline
    parser = AgentCore::MCP::SseParser.new(max_event_data_bytes: 10)

    assert_raises(AgentCore::MCP::SseParser::EventDataTooLargeError) do
      parser.feed("data: 12345\ndata: 67890\n\n")
    end
  end

  def test_invalid_max_buffer_bytes
    assert_raises(ArgumentError) { AgentCore::MCP::SseParser.new(max_buffer_bytes: 0) }
    assert_raises(ArgumentError) { AgentCore::MCP::SseParser.new(max_buffer_bytes: -1) }
  end

  def test_invalid_max_event_data_bytes
    assert_raises(ArgumentError) { AgentCore::MCP::SseParser.new(max_event_data_bytes: 0) }
    assert_raises(ArgumentError) { AgentCore::MCP::SseParser.new(max_event_data_bytes: -1) }
  end

  def test_consecutive_empty_lines_do_not_emit_empty_events
    events = []
    @parser.feed("data: hello\n\n\n\n") { |e| events << e }

    assert_equal 1, events.size
  end

  def test_data_space_stripping
    events = []
    # Per SSE spec: single leading space after colon is stripped
    @parser.feed("data:  two spaces\n\n") { |e| events << e }

    assert_equal 1, events.size
    assert_equal " two spaces", events[0][:data]
  end
end
