# frozen_string_literal: true

require "test_helper"
require "timeout"

class AgentCore::MCP::JsonRpcClientTest < Minitest::Test
  # A mock transport for testing JSON-RPC interactions.
  class MockTransport < AgentCore::MCP::Transport::Base
    attr_reader :sent_messages

    def initialize
      @sent_messages = []
      @started = false
      @closed = false
    end

    def start
      @started = true
      self
    end

    def send_message(hash)
      raise AgentCore::MCP::TransportError, "transport is not started" unless @started

      @sent_messages << hash
      true
    end

    def close(timeout_s: 2.0)
      @closed = true
      nil
    end

    # Simulate receiving a JSON-RPC response (called from test code).
    def simulate_response(json_string)
      on_stdout_line&.call(json_string)
    end
  end

  class QueueTransport < AgentCore::MCP::Transport::Base
    def initialize
      @queue = Queue.new
      @started = false
    end

    def start
      @started = true
      self
    end

    def send_message(hash)
      raise AgentCore::MCP::TransportError, "transport is not started" unless @started

      @queue << hash
      true
    end

    def close(timeout_s: 2.0)
      nil
    end

    def pop_message(timeout_s: 1.0)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s.to_f

      loop do
        return @queue.pop(true)
      rescue ThreadError
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Timeout::Error, "Timed out waiting for message" if now >= deadline

        sleep(0.001)
      end
    end
  end

  def setup
    @transport = MockTransport.new
    @client = AgentCore::MCP::JsonRpcClient.new(transport: @transport)
  end

  def test_initialize_requires_transport
    assert_raises(ArgumentError) do
      AgentCore::MCP::JsonRpcClient.new(transport: nil)
    end
  end

  def test_initialize_validates_timeout_s
    assert_raises(ArgumentError) do
      AgentCore::MCP::JsonRpcClient.new(transport: @transport, timeout_s: 0)
    end

    assert_raises(ArgumentError) do
      AgentCore::MCP::JsonRpcClient.new(transport: @transport, timeout_s: -1)
    end
  end

  def test_start_wires_stdout_callback
    @client.start

    assert_respond_to @transport.on_stdout_line, :call
  end

  def test_start_wires_close_callback
    @client.start

    assert_respond_to @transport.on_close, :call
  end

  def test_start_is_idempotent
    result1 = @client.start
    result2 = @client.start

    assert_same result1, result2
  end

  def test_start_does_not_deadlock_when_transport_emits_stdout_during_start
    transport = Class.new(MockTransport) do
      def start
        super
        on_stdout_line&.call(JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "result" => { "ok" => true } }))
        self
      end
    end.new

    client = AgentCore::MCP::JsonRpcClient.new(transport: transport)

    thread = Thread.new { client.start }
    refute_nil thread.join(1.0), "start should not deadlock"

    assert_same client, thread.value
  ensure
    client&.close
  end

  def test_start_after_close_raises
    @client.start
    @client.close

    assert_raises(AgentCore::MCP::ClosedError) { @client.start }
  end

  def test_request_sends_jsonrpc_message
    @client.start

    # Send request in a thread (it will block waiting for response)
    thread = Thread.new { @client.request("test/method", { "key" => "value" }, timeout_s: 0.5) }
    sleep(0.05)

    assert_equal 1, @transport.sent_messages.size
    msg = @transport.sent_messages.first

    assert_equal "2.0", msg["jsonrpc"]
    assert_equal "test/method", msg["method"]
    assert_equal({ "key" => "value" }, msg["params"])
    assert_kind_of Integer, msg["id"]

    thread.kill
    thread.join(0.1)
  end

  def test_request_returns_result
    @client.start

    thread = Thread.new { @client.request("test/method", {}, timeout_s: 1.0) }
    sleep(0.05)

    id = @transport.sent_messages.first["id"]
    @transport.simulate_response(JSON.generate({ "jsonrpc" => "2.0", "id" => id, "result" => { "data" => "ok" } }))

    result = thread.value
    assert_equal({ "data" => "ok" }, result)
  end

  def test_request_raises_on_error_response
    @client.start

    thread = Thread.new do
      assert_raises(AgentCore::MCP::JsonRpcError) do
        @client.request("test/method", {}, timeout_s: 1.0)
      end
    end
    sleep(0.05)

    id = @transport.sent_messages.first["id"]
    @transport.simulate_response(
      JSON.generate({
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => { "code" => -32600, "message" => "Invalid Request" },
      }),
    )

    thread.join(1.0)
  end

  def test_request_times_out
    @client.start

    assert_raises(AgentCore::MCP::TimeoutError) do
      @client.request("test/method", {}, timeout_s: 0.1)
    end
  end

  def test_request_before_start_raises
    assert_raises(AgentCore::MCP::TransportError) do
      @client.request("test/method")
    end
  end

  def test_request_after_close_raises
    @client.start
    @client.close

    assert_raises(AgentCore::MCP::ClosedError) do
      @client.request("test/method")
    end
  end

  def test_request_blank_method_raises
    @client.start

    assert_raises(ArgumentError) { @client.request("") }
    assert_raises(ArgumentError) { @client.request("  ") }
  end

  def test_notify_sends_message_without_id
    @client.start
    result = @client.notify("notifications/initialized")

    assert_equal true, result
    assert_equal 1, @transport.sent_messages.size

    msg = @transport.sent_messages.first
    assert_equal "2.0", msg["jsonrpc"]
    assert_equal "notifications/initialized", msg["method"]
    refute msg.key?("id")
  end

  def test_notify_with_params
    @client.start
    @client.notify("notifications/test", { "key" => "value" })

    msg = @transport.sent_messages.first
    assert_equal({ "key" => "value" }, msg["params"])
  end

  def test_notify_without_params
    @client.start
    @client.notify("notifications/test")

    msg = @transport.sent_messages.first
    refute msg.key?("params")
  end

  def test_notify_before_start_raises
    assert_raises(AgentCore::MCP::TransportError) do
      @client.notify("notifications/test")
    end
  end

  def test_notify_after_close_raises
    @client.start
    @client.close

    assert_raises(AgentCore::MCP::ClosedError) do
      @client.notify("notifications/test")
    end
  end

  def test_notify_blank_method_raises
    @client.start

    assert_raises(ArgumentError) { @client.notify("") }
  end

  def test_close_cancels_pending_requests
    @client.start

    thread = Thread.new do
      assert_raises(AgentCore::MCP::ClosedError) do
        @client.request("test/method", {}, timeout_s: 5.0)
      end
    end
    sleep(0.05)

    @client.close
    thread.join(1.0)
  end

  def test_close_is_idempotent
    @client.start
    @client.close
    @client.close
  end

  def test_transport_close_cancels_pending_requests
    @client.start

    thread = Thread.new do
      assert_raises(AgentCore::MCP::TransportError) do
        @client.request("test/method", {}, timeout_s: 5.0)
      end
    end
    sleep(0.05)

    # Simulate transport closing
    @transport.on_close.call({ error: "connection lost" })
    thread.join(1.0)
  end

  def test_on_notification_callback
    notifications = []
    client = AgentCore::MCP::JsonRpcClient.new(
      transport: @transport,
      on_notification: ->(msg) { notifications << msg },
    )
    client.start

    @transport.simulate_response(
      JSON.generate({ "jsonrpc" => "2.0", "method" => "notifications/progress", "params" => { "progress" => 50 } }),
    )

    sleep(0.05)
    assert_equal 1, notifications.size
    assert_equal "notifications/progress", notifications.first["method"]
  ensure
    client&.close
  end

  def test_non_notification_methods_ignored
    notifications = []
    client = AgentCore::MCP::JsonRpcClient.new(
      transport: @transport,
      on_notification: ->(msg) { notifications << msg },
    )
    client.start

    # Method that doesn't start with "notifications/" should be ignored
    @transport.simulate_response(
      JSON.generate({ "jsonrpc" => "2.0", "method" => "some/other", "params" => {} }),
    )

    sleep(0.05)
    assert_empty notifications
  ensure
    client&.close
  end

  def test_integer_string_id_mismatch_handling
    @client.start

    thread = Thread.new { @client.request("test/method", {}, timeout_s: 1.0) }
    sleep(0.05)

    id = @transport.sent_messages.first["id"]
    # Respond with string version of the integer ID
    @transport.simulate_response(
      JSON.generate({ "jsonrpc" => "2.0", "id" => id.to_s, "result" => "ok" }),
    )

    result = thread.value
    assert_equal "ok", result
  end

  def test_invalid_json_in_stdout_ignored
    @client.start

    # Should not raise
    @transport.simulate_response("not valid json{{{")
    @transport.simulate_response("")
    @transport.simulate_response("   ")
  end

  def test_increments_request_ids
    @client.start

    threads = 3.times.map do
      Thread.new do
        @client.request("test/method", {}, timeout_s: 0.1)
      rescue AgentCore::MCP::TimeoutError
        nil
      end
    end

    threads.each { |t| t.join(1.0) }

    # Filter to only request messages (non-nil id); timeout also sends cancel notifications (nil id).
    ids = @transport.sent_messages.filter_map { |m| m["id"] }
    assert_equal 3, ids.size
    assert_equal ids.uniq, ids
    assert_equal ids.sort, ids
  end

  def test_preserves_existing_stdout_callback
    original_calls = []
    @transport.on_stdout_line = ->(line) { original_calls << line }

    @client.start

    # Simulate a response — both the original callback and the client handler should fire
    @transport.on_stdout_line.call("test line")

    assert_equal ["test line"], original_calls
  end

  def test_request_is_thread_safe_under_concurrent_load
    transport = QueueTransport.new
    client = AgentCore::MCP::JsonRpcClient.new(transport: transport, timeout_s: 1.0)
    client.start

    n = 50
    results = Array.new(n)

    threads =
      n.times.map do |i|
        Thread.new do
          results[i] = client.request("test/method", { "i" => i }, timeout_s: 1.0)
        end
      end

    responder =
      Thread.new do
        n.times do
          msg = transport.pop_message(timeout_s: 1.0)
          id = msg.fetch("id")
          i = msg.dig("params", "i")

          sleep(0.001) # encourage out-of-order completion

          transport.on_stdout_line&.call(JSON.generate({ "jsonrpc" => "2.0", "id" => id, "result" => { "i" => i } }))
        end
      end

    threads.each { |t| t.join(2.0) }
    responder.join(2.0)

    assert_equal n, results.size
    results.each_with_index do |result, i|
      assert_equal({ "i" => i }, result)
    end
  ensure
    client&.close
  end
end
