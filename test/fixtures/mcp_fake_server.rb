# frozen_string_literal: true

require "json"

STDOUT.sync = true
STDERR.sync = true

def reply(id, result: nil, error: nil)
  msg = { "jsonrpc" => "2.0", "id" => id }
  if error
    msg["error"] = error
  else
    msg["result"] = result
  end

  STDOUT.write(JSON.generate(msg))
  STDOUT.write("\n")
  STDOUT.flush
end

TOOLS_PAGE_1 = [
  {
    "name" => "echo",
    "description" => "Echo text back.",
    "inputSchema" => {
      "type" => "object",
      "properties" => {
        "text" => { "type" => "string" },
        "mode" => { "type" => "string", "description" => "Set to 'error' to return isError=true" },
      },
      "required" => ["text"],
    },
  },
].freeze

TOOLS_PAGE_2 = [
  {
    "name" => "mixed.content",
    "description" => "Return text + non-text content blocks.",
    "inputSchema" => { "type" => "object", "properties" => {} },
  },
].freeze

STDIN.each_line do |line|
  line = line.to_s.strip
  next if line.empty?

  msg =
    begin
      JSON.parse(line)
    rescue JSON::ParserError
      next
    end
  next unless msg.is_a?(Hash)

  method_name = msg.fetch("method", "").to_s
  id = msg.fetch("id", nil)
  params = msg.fetch("params", nil)
  params = {} unless params.is_a?(Hash)

  if id.nil?
    # Notification
    next
  end

  case method_name
  when "initialize"
    protocol_version = params.fetch("protocolVersion", "2025-11-25").to_s
    result = {
      "protocolVersion" => protocol_version,
      "serverInfo" => { "name" => "mcp_fake_server", "version" => "1.0.0" },
      "capabilities" => { "tools" => {} },
      "instructions" => "Fake MCP server for tests.",
    }

    reply(id, result: result)
  when "tools/list"
    cursor = params.fetch("cursor", "").to_s
    if cursor.empty?
      reply(id, result: { "tools" => TOOLS_PAGE_1, "nextCursor" => "page2" })
    elsif cursor == "page2"
      reply(id, result: { "tools" => TOOLS_PAGE_2 })
    else
      reply(id, result: { "tools" => [] })
    end
  when "tools/call"
    tool_name = params.fetch("name", "").to_s
    arguments = params.fetch("arguments", {})
    arguments = {} unless arguments.is_a?(Hash)

    case tool_name
    when "echo"
      text = arguments.fetch("text", "").to_s
      is_error = arguments.fetch("mode", "").to_s == "error"

      reply(
        id,
        result: {
          "content" => [{ "type" => "text", "text" => text }],
          "structuredContent" => { "tool" => "echo", "arguments" => arguments },
          "isError" => is_error,
        },
      )
    when "mixed.content"
      reply(
        id,
        result: {
          "content" => [
            { "type" => "text", "text" => "hello" },
            { "type" => "resource_link", "uri" => "https://example.com/resource" },
            { "type" => "image", "mimeType" => "image/png", "data" => "AAAA" },
          ],
          "structuredContent" => { "ok" => true },
          "isError" => false,
        },
      )
    else
      reply(
        id,
        result: {
          "content" => [{ "type" => "text", "text" => "unknown tool" }],
          "structuredContent" => { "error" => "unknown tool" },
          "isError" => true,
        },
      )
    end
  else
    reply(id, error: { "code" => -32_601, "message" => "Method not found: #{method_name}" })
  end
end
