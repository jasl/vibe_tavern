# frozen_string_literal: true

require "test_helper"

class AgentCore::MCP::Transport::StdioTest < Minitest::Test
  def test_initialize_with_required_params
    transport = AgentCore::MCP::Transport::Stdio.new(command: "echo")
    assert_instance_of AgentCore::MCP::Transport::Stdio, transport
  end

  def test_initialize_with_all_params
    transport = AgentCore::MCP::Transport::Stdio.new(
      command: "echo",
      args: ["hello"],
      env: { "FOO" => "bar" },
      chdir: "/tmp",
      on_stdout_line: ->(_line) { },
      on_stderr_line: ->(_line) { },
    )
    assert_instance_of AgentCore::MCP::Transport::Stdio, transport
  end

  def test_start_raises_on_blank_command
    transport = AgentCore::MCP::Transport::Stdio.new(command: "   ")
    assert_raises(ArgumentError) { transport.start }
  end

  def test_start_and_close_with_cat
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    transport.start
    transport.close(timeout_s: 2.0)
  end

  def test_start_is_idempotent
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    result1 = transport.start
    result2 = transport.start
    assert_same result1, result2
  ensure
    transport&.close(timeout_s: 1.0)
  end

  def test_close_is_idempotent
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    transport.start
    transport.close(timeout_s: 1.0)
    transport.close(timeout_s: 1.0)
  end

  def test_close_without_start
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    # Should not raise
    transport.close(timeout_s: 1.0)
  end

  def test_start_after_close_raises
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    transport.close(timeout_s: 1.0)

    assert_raises(AgentCore::MCP::ClosedError) { transport.start }
  end

  def test_send_message_before_start_raises
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")

    assert_raises(AgentCore::MCP::TransportError) do
      transport.send_message({ "jsonrpc" => "2.0", "method" => "test" })
    end
  end

  def test_send_message_writes_json
    received = []
    transport = AgentCore::MCP::Transport::Stdio.new(
      command: "cat",
      on_stdout_line: ->(line) { received << line },
    )

    transport.start
    transport.send_message({ "jsonrpc" => "2.0", "id" => 1, "method" => "test" })

    # Give cat a moment to echo back
    sleep(0.1)
    transport.close(timeout_s: 2.0)

    assert_equal 1, received.size
    parsed = JSON.parse(received.first)
    assert_equal "2.0", parsed["jsonrpc"]
    assert_equal 1, parsed["id"]
    assert_equal "test", parsed["method"]
  end

  def test_send_message_returns_true
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    transport.start

    result = transport.send_message({ "jsonrpc" => "2.0", "method" => "test" })
    assert_equal true, result
  ensure
    transport&.close(timeout_s: 1.0)
  end

  def test_stderr_callback
    stderr_lines = []
    transport = AgentCore::MCP::Transport::Stdio.new(
      command: "sh",
      args: ["-c", "echo 'debug info' >&2 && sleep 0.5"],
      on_stderr_line: ->(line) { stderr_lines << line },
    )

    transport.start
    sleep(0.3)
    transport.close(timeout_s: 2.0)

    assert_includes stderr_lines, "debug info"
  end

  def test_on_close_callback
    close_details = nil
    transport = AgentCore::MCP::Transport::Stdio.new(
      command: "sh",
      args: ["-c", "exit 0"],
    )
    transport.on_close = ->(details) { close_details = details }

    transport.start
    sleep(0.3)

    # Process should have exited, triggering on_close
    refute_nil close_details
    assert_equal 0, close_details[:exitstatus]
  ensure
    transport&.close(timeout_s: 1.0)
  end

  def test_close_negative_timeout_returns_nil
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    # Negative timeout causes ArgumentError which is rescued → nil
    result = transport.close(timeout_s: -1.0)
    assert_nil result
  end

  def test_env_normalization
    received = []
    transport = AgentCore::MCP::Transport::Stdio.new(
      command: "sh",
      args: ["-c", "echo $MY_VAR"],
      env: { MY_VAR: "hello_world" },
      on_stdout_line: ->(line) { received << line },
    )

    transport.start
    sleep(0.2)
    transport.close(timeout_s: 2.0)

    assert_includes received, "hello_world"
  end

  def test_inherits_from_base
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    assert_kind_of AgentCore::MCP::Transport::Base, transport
  end

  def test_close_forcefully_kills_long_running_process
    transport = AgentCore::MCP::Transport::Stdio.new(
      command: "sh",
      args: ["-c", "trap '' TERM; sleep 60"],
    )

    transport.start
    sleep(0.1)

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    transport.close(timeout_s: 0.5)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    # Should not wait the full 60 seconds
    assert elapsed < 10, "close took too long: #{elapsed}s"
  end

  def test_send_message_after_close_raises
    transport = AgentCore::MCP::Transport::Stdio.new(command: "cat")
    transport.start
    transport.close(timeout_s: 1.0)

    assert_raises(AgentCore::MCP::TransportError) do
      transport.send_message({ "jsonrpc" => "2.0", "method" => "test" })
    end
  end
end
