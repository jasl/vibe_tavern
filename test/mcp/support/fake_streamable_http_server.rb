# frozen_string_literal: true

require "json"
require "securerandom"
require "socket"

class McpFakeStreamableHttpServer
  attr_reader :initialize_count,
              :tools_list_count,
              :tools_call_count,
              :last_event_id_requests,
              :not_found_count,
              :cancelled_requests

  def initialize(
    tools_call_mode:,
    retry_ms: nil,
    invalidate_session_after_first_tools_list: false,
    tools_call_delay_s: nil,
    tools_call_result_text_bytes: nil
  )
    @tools_call_mode = tools_call_mode
    @retry_ms = retry_ms
    @invalidate_session_after_first_tools_list = invalidate_session_after_first_tools_list
    @tools_call_delay_s = tools_call_delay_s.nil? ? nil : Float(tools_call_delay_s)
    @tools_call_result_text_bytes =
      tools_call_result_text_bytes.nil? ? nil : Integer(tools_call_result_text_bytes)

    @initialize_count = 0
    @tools_list_count = 0
    @tools_call_count = 0
    @last_event_id_requests = []
    @not_found_count = 0
    @cancelled_requests = []

    @sessions = {}
    @pending_sse = {}
    @mutex = Mutex.new

    @closing = false
    @connection_threads = []

    @tcp_server = TCPServer.new("127.0.0.1", 0)
    _addr, @port, = @tcp_server.addr

    @accept_thread = Thread.new { accept_loop }
  end

  def url
    "http://127.0.0.1:#{@port}/mcp"
  end

  def close
    threads = []

    @mutex.synchronize do
      @closing = true
    end

    @tcp_server.close
    @accept_thread.join

    @mutex.synchronize do
      threads = @connection_threads.dup
    end

    threads.each { |t| t.join }
  rescue IOError, Errno::EBADF
    nil
  end

  private

  def accept_loop
    loop do
      break if closing?

      ready = IO.select([@tcp_server], nil, nil, 0.1)
      next unless ready

      sock = @tcp_server.accept_nonblock(exception: false)
      next if sock == :wait_readable

      thread =
        Thread.new do
          handle_connection(sock)
        ensure
          @mutex.synchronize { @connection_threads.delete(Thread.current) }
        end

      @mutex.synchronize { @connection_threads << thread }
    rescue IOError, Errno::EBADF
      break
    end
  end

  def closing?
    @mutex.synchronize { @closing }
  end

  def handle_connection(sock)
    request = read_http_request(sock)
    return unless request

    method = request.fetch(:method)
    headers = request.fetch(:headers)
    body = request.fetch(:body)

    case method
    when "POST"
      handle_post(sock, headers, body)
    when "GET"
      handle_get(sock, headers)
    when "DELETE"
      handle_delete(sock, headers)
    else
      write_response(sock, status: 405, headers: { "Content-Type" => "application/json" }, body: "{}")
    end
  ensure
    sock.close rescue nil
  end

  def handle_post(sock, headers, body)
    accept = headers.fetch("accept", "")
    unless accept.include?("application/json") && accept.include?("text/event-stream")
      write_response(sock, status: 406, headers: { "Content-Type" => "application/json" }, body: "{}")
      return
    end

    msg = JSON.parse(body)
    method_name = msg.fetch("method", "")
    id = msg.fetch("id", nil)

    if method_name == "initialize"
      handle_initialize(sock, msg)
      return
    end

    protocol_version = headers.fetch("mcp-protocol-version", nil)
    session_id = headers.fetch("mcp-session-id", nil)
    if protocol_version.to_s.strip.empty?
      write_response(sock, status: 400, headers: { "Content-Type" => "application/json" }, body: "{}")
      return
    end

    unless session_valid?(session_id)
      @mutex.synchronize { @not_found_count += 1 }
      write_response(sock, status: 404, headers: { "Content-Type" => "application/json" }, body: "{}")
      return
    end

    if id.nil? || method_name.start_with?("notifications/")
      if method_name == "notifications/cancelled"
        params = msg.fetch("params", {})
        params = {} unless params.is_a?(Hash)
        @mutex.synchronize { @cancelled_requests << params }
      end

      write_response(sock, status: 202, headers: {}, body: "")
      return
    end

    case method_name
    when "tools/list"
      handle_tools_list(sock, id, msg.fetch("params", {}), session_id)
    when "tools/call"
      handle_tools_call(sock, id, msg.fetch("params", {}), session_id)
    else
      reply(sock, id, error: { "code" => -32_601, "message" => "Method not found: #{method_name}" })
    end
  rescue JSON::ParserError
    write_response(sock, status: 400, headers: { "Content-Type" => "application/json" }, body: "{}")
  end

  def handle_get(sock, headers)
    accept = headers.fetch("accept", "")
    unless accept.include?("text/event-stream")
      write_response(sock, status: 406, headers: { "Content-Type" => "application/json" }, body: "{}")
      return
    end

    protocol_version = headers.fetch("mcp-protocol-version", nil)
    session_id = headers.fetch("mcp-session-id", nil)
    last_event_id = headers.fetch("last-event-id", nil)

    @mutex.synchronize { @last_event_id_requests << last_event_id.to_s }

    if protocol_version.to_s.strip.empty?
      write_response(sock, status: 400, headers: { "Content-Type" => "application/json" }, body: "{}")
      return
    end

    unless session_valid?(session_id)
      @mutex.synchronize { @not_found_count += 1 }
      write_response(sock, status: 404, headers: { "Content-Type" => "application/json" }, body: "{}")
      return
    end

    payload = nil

    @mutex.synchronize do
      payload = @pending_sse.dig(session_id.to_s, last_event_id.to_s)
    end

    write_sse_headers(sock)

    if payload
      sock.write("data: #{payload}\n\n")
      sock.flush
    end
  end

  def handle_delete(sock, headers)
    protocol_version = headers.fetch("mcp-protocol-version", nil)
    session_id = headers.fetch("mcp-session-id", nil)

    if protocol_version.to_s.strip.empty? || session_id.to_s.strip.empty?
      write_response(sock, status: 400, headers: { "Content-Type" => "application/json" }, body: "{}")
      return
    end

    @mutex.synchronize do
      @sessions.delete(session_id.to_s)
      @pending_sse.delete(session_id.to_s)
    end

    write_response(sock, status: 200, headers: { "Content-Type" => "application/json" }, body: "{\"ok\":true}")
  end

  def handle_initialize(sock, msg)
    @mutex.synchronize { @initialize_count += 1 }

    session_id = SecureRandom.uuid
    @mutex.synchronize { @sessions[session_id] = true }

    protocol_version = msg.dig("params", "protocolVersion").to_s
    protocol_version = "2025-11-25" if protocol_version.strip.empty?

    result = {
      "protocolVersion" => protocol_version,
      "serverInfo" => { "name" => "fake_streamable_http", "version" => "1.0.0" },
      "capabilities" => { "tools" => {} },
      "instructions" => "Fake Streamable HTTP MCP server for tests.",
    }

    reply(sock, msg.fetch("id"), result: result, extra_headers: { "MCP-Session-Id" => session_id })
  end

  def handle_tools_list(sock, id, params, session_id)
    @mutex.synchronize { @tools_list_count += 1 }

    if @invalidate_session_after_first_tools_list && @tools_list_count == 1
      @mutex.synchronize { @sessions.delete(session_id.to_s) }
    end

    params = params.is_a?(Hash) ? params : {}
    cursor = params.fetch("cursor", "").to_s

    if cursor.strip.empty?
      tools = [
        {
          "name" => "echo",
          "description" => "Echo text back.",
          "inputSchema" => {
            "type" => "object",
            "properties" => { "text" => { "type" => "string" } },
            "required" => ["text"],
          },
        },
      ]

      reply(sock, id, result: { "tools" => tools, "nextCursor" => "page2" })
    elsif cursor == "page2"
      tools = [
        {
          "name" => "mixed.content",
          "description" => "Return text + non-text content blocks.",
          "inputSchema" => { "type" => "object", "properties" => {} },
        },
      ]

      reply(sock, id, result: { "tools" => tools })
    else
      reply(sock, id, result: { "tools" => [] })
    end
  end

  def handle_tools_call(sock, id, params, session_id)
    @mutex.synchronize { @tools_call_count += 1 }

    delay_s = @tools_call_delay_s
    sleep(delay_s) if delay_s && delay_s.positive?

    name = params.fetch("name", "").to_s
    args = params.fetch("arguments", {})
    args = {} unless args.is_a?(Hash)

    response =
      {
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => {
          "content" => [
            {
              "type" => "text",
              "text" =>
                if @tools_call_result_text_bytes
                  "a" * @tools_call_result_text_bytes
                else
                  "#{name}: #{args.fetch("text", "")}"
                end,
            },
          ],
          "structuredContent" => { "tool" => name, "arguments" => args },
          "isError" => false,
        },
      }

    case @tools_call_mode
    when :json
      reply(sock, id, result: response.fetch("result"))
    when :sse_single_post
      write_sse_headers(sock)
      sock.write("data: #{JSON.generate(response)}\n\n")
      sock.flush
    when :sse_resume_via_get
      event_id = SecureRandom.hex(8)

      @mutex.synchronize do
        @pending_sse[session_id.to_s] ||= {}
        @pending_sse[session_id.to_s][event_id] = JSON.generate(response)
      end

      write_sse_headers(sock)
      sock.write("id: #{event_id}\n")
      sock.write("retry: #{@retry_ms}\n") if @retry_ms
      sock.write("data:\n\n")
      sock.flush
    when :sse_invalid_json
      write_sse_headers(sock)
      sock.write("data: {\n\n")
      sock.flush
    else
      raise "unknown tools_call_mode: #{@tools_call_mode.inspect}"
    end
  end

  def reply(sock, id, result: nil, error: nil, extra_headers: nil)
    msg = { "jsonrpc" => "2.0", "id" => id }
    if error
      msg["error"] = error
    else
      msg["result"] = result
    end

    headers = { "Content-Type" => "application/json" }
    headers.merge!(extra_headers) if extra_headers

    write_response(sock, status: 200, headers: headers, body: JSON.generate(msg))
  end

  def session_valid?(session_id)
    sid = session_id.to_s
    return false if sid.strip.empty?

    @mutex.synchronize { @sessions.key?(sid) }
  end

  def write_sse_headers(sock)
    headers = {
      "Content-Type" => "text/event-stream",
      "Cache-Control" => "no-cache",
      "Connection" => "close",
    }

    write_response(sock, status: 200, headers: headers, body: nil)
  end

  def read_http_request(sock)
    header_blob = +"".b

    while !header_blob.include?("\r\n\r\n")
      chunk = sock.readpartial(1024)
      header_blob << chunk
    end

    head, rest = header_blob.split("\r\n\r\n", 2)
    lines = head.to_s.split("\r\n")
    request_line = lines.shift.to_s
    method, _path, _version = request_line.split(" ", 3)

    headers = {}
    lines.each do |line|
      k, v = line.split(":", 2)
      next unless k && v

      headers[k.strip.downcase] = v.strip
    end

    body = rest.to_s.b

    if headers["transfer-encoding"].to_s.downcase == "chunked"
      body = read_chunked_body(sock, body)
    else
      content_length = headers.fetch("content-length", "0").to_i
      while body.bytesize < content_length
        body << sock.readpartial(content_length - body.bytesize)
      end
      body = body.byteslice(0, content_length).to_s
    end

    { method: method.to_s, headers: headers, body: body.to_s }
  rescue EOFError
    nil
  end

  def read_chunked_body(sock, initial)
    buf = initial.to_s.b
    out = +"".b

    loop do
      line, buf = read_line_from(buf, sock)
      size_hex = line.to_s.strip
      size = size_hex.to_i(16)
      break if size == 0

      while buf.bytesize < size + 2
        buf << sock.readpartial(1024)
      end

      out << buf.byteslice(0, size)
      buf = buf.byteslice(size + 2, buf.bytesize - size - 2) || +"".b
    end

    out.to_s
  end

  def read_line_from(buf, sock)
    while (idx = buf.index("\r\n")).nil?
      buf << sock.readpartial(1024)
    end

    line = buf.byteslice(0, idx).to_s
    rest = buf.byteslice(idx + 2, buf.bytesize - idx - 2) || +"".b
    [line, rest]
  end

  def write_response(sock, status:, headers:, body:)
    reason =
      case status
      when 200 then "OK"
      when 202 then "Accepted"
      when 400 then "Bad Request"
      when 404 then "Not Found"
      when 405 then "Method Not Allowed"
      when 406 then "Not Acceptable"
      else "OK"
      end

    sock.write("HTTP/1.1 #{status} #{reason}\r\n")
    headers.each do |k, v|
      sock.write("#{k}: #{v}\r\n")
    end

    if body
      body = body.to_s
      sock.write("Content-Length: #{body.bytesize}\r\n")
    end

    sock.write("\r\n")
    sock.write(body) if body
    sock.flush
  end
end
