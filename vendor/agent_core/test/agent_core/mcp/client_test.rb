# frozen_string_literal: true

require "test_helper"

class AgentCore::MCP::ClientTest < Minitest::Test
  # A mock transport that auto-responds to JSON-RPC messages.
  class AutoRespondTransport < AgentCore::MCP::Transport::Base
    attr_reader :sent_messages
    attr_accessor :responses

    def initialize
      @sent_messages = []
      @started = false
      @closed = false
      @responses = {}
    end

    def start
      @started = true
      self
    end

    def send_message(hash)
      @sent_messages << hash

      id = hash["id"]
      method_name = hash["method"]

      return true unless id

      response = @responses[method_name]
      if response
        Thread.new do
          sleep(0.01)
          result = response.is_a?(Proc) ? response.call(hash) : response
          on_stdout_line&.call(JSON.generate({ "jsonrpc" => "2.0", "id" => id, "result" => result }))
        end
      end

      true
    end

    def close(timeout_s: 2.0)
      @closed = true
      nil
    end
  end

  def setup
    @transport = AutoRespondTransport.new
    @transport.responses = {
      "initialize" => {
        "protocolVersion" => AgentCore::MCP::DEFAULT_PROTOCOL_VERSION,
        "serverInfo" => { "name" => "test-server", "version" => "1.0" },
        "capabilities" => { "tools" => {} },
        "instructions" => "Be helpful.",
      },
    }
  end

  def test_initialize_requires_transport
    assert_raises(ArgumentError) do
      AgentCore::MCP::Client.new(transport: nil)
    end
  end

  def test_initialize_validates_timeout_s
    assert_raises(ArgumentError) do
      AgentCore::MCP::Client.new(transport: @transport, timeout_s: 0)
    end
  end

  def test_start_performs_initialize_handshake
    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    init_msg = @transport.sent_messages.find { |m| m["method"] == "initialize" }
    refute_nil init_msg
    assert_equal AgentCore::MCP::DEFAULT_PROTOCOL_VERSION, init_msg["params"]["protocolVersion"]
  ensure
    client&.close
  end

  def test_start_stores_server_info
    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    assert_equal({ "name" => "test-server", "version" => "1.0" }, client.server_info)
    assert_equal({ "tools" => {} }, client.server_capabilities)
    assert_equal "Be helpful.", client.instructions
  ensure
    client&.close
  end

  def test_start_sends_initialized_notification
    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    # Wait briefly for the notification to be sent
    sleep(0.05)

    notif = @transport.sent_messages.find { |m| m["method"] == "notifications/initialized" }
    refute_nil notif
    refute notif.key?("id")
  ensure
    client&.close
  end

  def test_start_is_idempotent
    client = AgentCore::MCP::Client.new(transport: @transport)
    result1 = client.start
    result2 = client.start

    assert_same result1, result2
  ensure
    client&.close
  end

  def test_start_negotiates_protocol_version
    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    assert_equal AgentCore::MCP::DEFAULT_PROTOCOL_VERSION, client.protocol_version
  ensure
    client&.close
  end

  def test_start_rejects_unsupported_protocol_version
    @transport.responses["initialize"] = {
      "protocolVersion" => "1999-01-01",
      "serverInfo" => {},
    }

    client = AgentCore::MCP::Client.new(transport: @transport)

    assert_raises(AgentCore::MCP::ProtocolVersionNotSupportedError) do
      client.start
    end
  end

  def test_default_client_info
    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    init_msg = @transport.sent_messages.find { |m| m["method"] == "initialize" }
    client_info = init_msg["params"]["clientInfo"]

    assert_equal "agent_core", client_info["name"]
    assert_equal AgentCore::VERSION.to_s, client_info["version"]
  ensure
    client&.close
  end

  def test_custom_client_info
    client = AgentCore::MCP::Client.new(
      transport: @transport,
      client_info: { "name" => "my-app", "version" => "2.0" },
    )
    client.start

    init_msg = @transport.sent_messages.find { |m| m["method"] == "initialize" }
    client_info = init_msg["params"]["clientInfo"]

    assert_equal "my-app", client_info["name"]
    assert_equal "2.0", client_info["version"]
  ensure
    client&.close
  end

  def test_list_tools
    @transport.responses["tools/list"] = {
      "tools" => [
        { "name" => "read_file", "description" => "Read a file", "inputSchema" => {} },
      ],
    }

    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    result = client.list_tools
    assert_equal 1, result["tools"].size
    assert_equal "read_file", result["tools"].first["name"]
  ensure
    client&.close
  end

  def test_list_tools_with_cursor
    @transport.responses["tools/list"] = ->(msg) do
      params = msg["params"] || {}
      if params["cursor"] == "page2"
        { "tools" => [{ "name" => "tool_b" }] }
      else
        { "tools" => [{ "name" => "tool_a" }], "nextCursor" => "page2" }
      end
    end

    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    result = client.list_tools(cursor: "page2")
    assert_equal "tool_b", result["tools"].first["name"]
  ensure
    client&.close
  end

  def test_call_tool
    @transport.responses["tools/call"] = {
      "content" => [{ "type" => "text", "text" => "file contents" }],
    }

    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    result = client.call_tool(name: "read_file", arguments: { "path" => "/etc/hosts" })
    assert_equal "text", result["content"].first["type"]
    assert_equal "file contents", result["content"].first["text"]
  ensure
    client&.close
  end

  def test_call_tool_requires_name
    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start

    assert_raises(ArgumentError) { client.call_tool(name: "") }
    assert_raises(ArgumentError) { client.call_tool(name: "  ") }
  ensure
    client&.close
  end

  def test_close
    client = AgentCore::MCP::Client.new(transport: @transport)
    client.start
    client.close
  end

  def test_sets_transport_protocol_version
    transport = AutoRespondTransport.new
    transport.responses = @transport.responses

    # Add protocol_version= method dynamically
    protocol_version_set = nil
    transport.define_singleton_method(:protocol_version=) do |v|
      protocol_version_set = v
    end

    client = AgentCore::MCP::Client.new(transport: transport)
    client.start

    assert_equal AgentCore::MCP::DEFAULT_PROTOCOL_VERSION, protocol_version_set
  ensure
    client&.close
  end
end
