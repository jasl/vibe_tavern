# frozen_string_literal: true

require "test_helper"

class AgentCore::MCP::Transport::BaseTest < Minitest::Test
  def setup
    @transport = AgentCore::MCP::Transport::Base.new
  end

  def test_start_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) { @transport.start }
  end

  def test_send_message_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) { @transport.send_message({}) }
  end

  def test_close_raises_not_implemented
    assert_raises(AgentCore::NotImplementedError) { @transport.close }
  end

  def test_close_accepts_timeout_s_keyword
    assert_raises(AgentCore::NotImplementedError) { @transport.close(timeout_s: 5.0) }
  end

  def test_on_stdout_line_accessor
    callback = ->(_line) { }

    @transport.on_stdout_line = callback
    assert_equal callback, @transport.on_stdout_line
  end

  def test_on_stderr_line_accessor
    callback = ->(_line) { }

    @transport.on_stderr_line = callback
    assert_equal callback, @transport.on_stderr_line
  end

  def test_on_close_accessor
    callback = ->(_details) { }

    @transport.on_close = callback
    assert_equal callback, @transport.on_close
  end

  def test_callbacks_default_to_nil
    assert_nil @transport.on_stdout_line
    assert_nil @transport.on_stderr_line
    assert_nil @transport.on_close
  end

  def test_error_messages_include_class_name
    klass = Class.new(AgentCore::MCP::Transport::Base)

    transport = klass.new
    error = assert_raises(AgentCore::NotImplementedError) { transport.start }
    assert_includes error.message, "#start must be implemented"
  end
end
