# frozen_string_literal: true

require "test_helper"
require "webrick"

begin
  require "httpx"
rescue LoadError
  # Optional dependency — tests below will be skipped when missing.
end

require "agent_core/mcp/transport/streamable_http"

class AgentCore::MCP::Transport::StreamableHttpIntegrationTest < Minitest::Test
  class ScriptedServer
    class AnyMethodServlet < WEBrick::HTTPServlet::AbstractServlet
      def initialize(server, handler)
        super(server)
        @handler = handler
      end

      def do_GET(req, res) = @handler.call(req, res)
      def do_POST(req, res) = @handler.call(req, res)
      def do_DELETE(req, res) = @handler.call(req, res)
    end

    def initialize(responders)
      @responders = responders.dup
      @mutex = Mutex.new
      @requests = []

      @session_id = "sess_test"
      @tools_list_request_id = nil

      @server =
        WEBrick::HTTPServer.new(
          Port: 0,
          BindAddress: "127.0.0.1",
          Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::FATAL),
          AccessLog: [],
        )

      handler = ->(req, res) { handle(req, res) }
      @server.mount "/mcp", AnyMethodServlet, handler

      @thread = Thread.new { @server.start }
    end

    attr_reader :requests, :session_id
    attr_accessor :tools_list_request_id

    def url
      "http://127.0.0.1:#{@server.config[:Port]}/mcp"
    end

    def shutdown
      @server.shutdown
      @thread.join(1.0)
    end

    private

    def handle(req, res)
      info = {
        method: req.request_method,
        headers: normalize_headers(req),
        body: req.body.to_s,
      }

      responder = nil
      @mutex.synchronize do
        @requests << info
        responder = @responders.shift
      end

      unless responder
        res.status = 500
        res["Content-Type"] = "text/plain"
        res.body = "Unexpected request: #{req.request_method}"
        return
      end

      responder.call(req, res, self)
    rescue StandardError => e
      res.status = 500
      res["Content-Type"] = "text/plain"
      res.body = "Server error: #{e.class}: #{e.message}"
    end

    def normalize_headers(req)
      req.header.each_with_object({}) do |(k, v), out|
        out[k.to_s.downcase] = Array(v).join(", ")
      end
    end
  end

  def setup
    skip "httpx is not available" unless defined?(::HTTPX)
  end

  def test_json_response_path_end_to_end
    server =
      ScriptedServer.new(
        [
          method(:handle_initialize_json),
          method(:handle_initialized_notification),
          method(:handle_tools_list_json),
          method(:handle_delete_session),
        ],
      )

    transport =
      AgentCore::MCP::Transport::StreamableHttp.new(
        url: server.url,
        timeout_s: 1.0,
        open_timeout_s: 1.0,
        read_timeout_s: 1.0,
        sleep_fn: ->(_seconds) { nil },
      )

    client = AgentCore::MCP::Client.new(transport: transport)
    client.start

    result = client.list_tools
    assert_equal [], result.fetch("tools")

    client.close
    client = nil

    assert_request_headers!(server.requests)
  ensure
    client&.close
    server&.shutdown
  end

  def test_sse_response_path_end_to_end
    server =
      ScriptedServer.new(
        [
          method(:handle_initialize_json),
          method(:handle_initialized_notification),
          method(:handle_tools_list_sse_complete),
          method(:handle_delete_session),
        ],
      )

    transport =
      AgentCore::MCP::Transport::StreamableHttp.new(
        url: server.url,
        timeout_s: 1.0,
        open_timeout_s: 1.0,
        read_timeout_s: 1.0,
        sleep_fn: ->(_seconds) { nil },
      )

    client = AgentCore::MCP::Client.new(transport: transport)
    client.start

    result = client.list_tools
    assert_equal ["tool_a"], result.fetch("tools").map { |t| t.fetch("name") }
  ensure
    client&.close
    server&.shutdown
  end

  def test_sse_reconnects_via_get_when_stream_ends_before_response
    server =
      ScriptedServer.new(
        [
          method(:handle_initialize_json),
          method(:handle_initialized_notification),
          method(:handle_tools_list_sse_incomplete),
          method(:handle_tools_list_get_reconnect),
          method(:handle_delete_session),
        ],
      )

    transport =
      AgentCore::MCP::Transport::StreamableHttp.new(
        url: server.url,
        timeout_s: 1.0,
        open_timeout_s: 1.0,
        read_timeout_s: 1.0,
        sleep_fn: ->(_seconds) { nil },
      )

    client = AgentCore::MCP::Client.new(transport: transport)
    client.start

    result = client.list_tools
    assert_equal ["tool_b"], result.fetch("tools").map { |t| t.fetch("name") }

    get_req = server.requests.find { |r| r[:method] == "GET" }
    refute_nil get_req
    assert_equal "evt_1", get_req[:headers]["last-event-id"]
  ensure
    client&.close
    server&.shutdown
  end

  private

  def handle_initialize_json(req, res, server)
    assert_equal "POST", req.request_method
    assert_equal AgentCore::MCP::HTTP_ACCEPT_POST, req.header["accept"]&.first.to_s

    msg = JSON.parse(req.body.to_s)
    assert_equal "initialize", msg.fetch("method")

    response =
      {
        "jsonrpc" => "2.0",
        "id" => msg.fetch("id"),
        "result" => {
          "protocolVersion" => AgentCore::MCP::DEFAULT_PROTOCOL_VERSION,
          "serverInfo" => { "name" => "test-server", "version" => "1.0" },
          "capabilities" => { "tools" => {} },
          "instructions" => "Be helpful.",
        },
      }

    res.status = 200
    res["Content-Type"] = "application/json"
    res[AgentCore::MCP::MCP_SESSION_ID_HEADER] = server.session_id
    res.body = JSON.generate(response)
  end

  def handle_initialized_notification(req, res, _server)
    assert_equal "POST", req.request_method

    msg = JSON.parse(req.body.to_s)
    assert_equal "notifications/initialized", msg.fetch("method")
    refute msg.key?("id")

    res.status = 204
    res["Content-Type"] = "text/plain"
    res.body = ""
  end

  def handle_tools_list_json(req, res, _server)
    assert_equal "POST", req.request_method

    msg = JSON.parse(req.body.to_s)
    assert_equal "tools/list", msg.fetch("method")

    response =
      {
        "jsonrpc" => "2.0",
        "id" => msg.fetch("id"),
        "result" => { "tools" => [] },
      }

    res.status = 200
    res["Content-Type"] = "application/json"
    res.body = JSON.generate(response)
  end

  def handle_tools_list_sse_complete(req, res, _server)
    assert_equal "POST", req.request_method

    msg = JSON.parse(req.body.to_s)
    assert_equal "tools/list", msg.fetch("method")

    response =
      {
        "jsonrpc" => "2.0",
        "id" => msg.fetch("id"),
        "result" => {
          "tools" => [
            { "name" => "tool_a", "description" => "A", "inputSchema" => {} },
          ],
        },
      }

    res.status = 200
    res["Content-Type"] = "text/event-stream"
    res.body = sse_event(data: response)
  end

  def handle_tools_list_sse_incomplete(req, res, server)
    assert_equal "POST", req.request_method

    msg = JSON.parse(req.body.to_s)
    assert_equal "tools/list", msg.fetch("method")

    server.tools_list_request_id = msg.fetch("id")

    notification =
      {
        "jsonrpc" => "2.0",
        "method" => "notifications/progress",
        "params" => { "progress" => 50 },
      }

    res.status = 200
    res["Content-Type"] = "text/event-stream"
    res.body = sse_event(data: notification, id: "evt_1")
  end

  def handle_tools_list_get_reconnect(req, res, server)
    assert_equal "GET", req.request_method
    assert_equal "evt_1", req.header["last-event-id"]&.first.to_s

    response =
      {
        "jsonrpc" => "2.0",
        "id" => server.tools_list_request_id,
        "result" => {
          "tools" => [
            { "name" => "tool_b", "description" => "B", "inputSchema" => {} },
          ],
        },
      }

    res.status = 200
    res["Content-Type"] = "text/event-stream"
    res.body = sse_event(data: response)
  end

  def handle_delete_session(req, res, _server)
    assert_equal "DELETE", req.request_method

    res.status = 200
    res["Content-Type"] = "application/json"
    res.body = JSON.generate({ ok: true })
  end

  def sse_event(data:, id: nil)
    json = data.is_a?(String) ? data : JSON.generate(data)
    raise ArgumentError, "SSE data must be single-line JSON" if json.include?("\n") || json.include?("\r")

    lines = []
    lines << "id: #{id}" if id
    lines << "data: #{json}"
    lines.join("\n") + "\n\n"
  end

  def assert_request_headers!(requests)
    init = requests.find { |r| r[:method] == "POST" && JSON.parse(r[:body])["method"] == "initialize" }
    refute_nil init
    refute init[:headers].key?("mcp-protocol-version")
    refute init[:headers].key?("mcp-session-id")

    notif = requests.find { |r| r[:method] == "POST" && JSON.parse(r[:body])["method"] == "notifications/initialized" }
    refute_nil notif
    assert_equal AgentCore::MCP::DEFAULT_PROTOCOL_VERSION, notif[:headers].fetch("mcp-protocol-version")
    assert_equal "sess_test", notif[:headers].fetch("mcp-session-id")

    list = requests.find { |r| r[:method] == "POST" && JSON.parse(r[:body])["method"] == "tools/list" }
    refute_nil list
    assert_equal AgentCore::MCP::DEFAULT_PROTOCOL_VERSION, list[:headers].fetch("mcp-protocol-version")
    assert_equal "sess_test", list[:headers].fetch("mcp-session-id")

    del = requests.find { |r| r[:method] == "DELETE" }
    refute_nil del
    assert_equal AgentCore::MCP::HTTP_ACCEPT_GET, del[:headers].fetch("accept")
    assert_equal AgentCore::MCP::DEFAULT_PROTOCOL_VERSION, del[:headers].fetch("mcp-protocol-version")
    assert_equal "sess_test", del[:headers].fetch("mcp-session-id")
  end
end
