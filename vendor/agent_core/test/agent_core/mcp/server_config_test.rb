# frozen_string_literal: true

require "test_helper"

class AgentCore::MCP::ServerConfigTest < Minitest::Test
  def test_stdio_minimal
    config = AgentCore::MCP::ServerConfig.new(id: "my-server", command: "echo")

    assert_equal "my-server", config.id
    assert_equal :stdio, config.transport
    assert_equal "echo", config.command
    assert_equal [], config.args
    assert_equal({}, config.env)
    assert_nil config.env_provider
    assert_nil config.chdir
    assert_nil config.url
    assert_equal AgentCore::MCP::DEFAULT_PROTOCOL_VERSION, config.protocol_version
    assert_equal AgentCore::MCP::DEFAULT_TIMEOUT_S, config.timeout_s
  end

  def test_stdio_full
    callback = ->(_line) { }
    env_provider = -> { { "FOO" => "bar" } }

    config = AgentCore::MCP::ServerConfig.new(
      id: "my-server",
      transport: :stdio,
      command: "node",
      args: ["server.js"],
      env: { "NODE_ENV" => "production" },
      env_provider: env_provider,
      chdir: "/app",
      on_stdout_line: callback,
      on_stderr_line: callback,
      client_info: { "name" => "test" },
      capabilities: { "tools" => {} },
    )

    assert_equal :stdio, config.transport
    assert_equal "node", config.command
    assert_equal ["server.js"], config.args
    assert_equal({ "NODE_ENV" => "production" }, config.env)
    assert_same env_provider, config.env_provider
    assert_equal "/app", config.chdir
    assert_same callback, config.on_stdout_line
    assert_same callback, config.on_stderr_line
    assert_equal({ "name" => "test" }, config.client_info)
    assert_equal({ "tools" => {} }, config.capabilities)
  end

  def test_streamable_http_minimal
    config = AgentCore::MCP::ServerConfig.new(
      id: "remote",
      transport: :streamable_http,
      url: "https://example.com/mcp",
    )

    assert_equal "remote", config.id
    assert_equal :streamable_http, config.transport
    assert_equal "https://example.com/mcp", config.url
    assert_nil config.command
    assert_equal [], config.args
    assert_equal({}, config.env)
    assert_nil config.chdir
    assert_equal({}, config.headers)
  end

  def test_streamable_http_full
    provider = -> { { "Authorization" => "Bearer token" } }

    config = AgentCore::MCP::ServerConfig.new(
      id: "remote",
      transport: :streamable_http,
      url: "https://example.com/mcp",
      headers: { "X-Custom" => "value" },
      headers_provider: provider,
      open_timeout_s: 5.0,
      read_timeout_s: 30.0,
      sse_max_reconnects: 10,
      max_response_bytes: 1_000_000,
    )

    assert_equal({ "X-Custom" => "value" }, config.headers)
    assert_same provider, config.headers_provider
    assert_equal 5.0, config.open_timeout_s
    assert_equal 30.0, config.read_timeout_s
    assert_equal 10, config.sse_max_reconnects
    assert_equal 1_000_000, config.max_response_bytes
  end

  def test_id_is_required
    assert_raises(ArgumentError) { AgentCore::MCP::ServerConfig.new(id: "", command: "echo") }
    assert_raises(ArgumentError) { AgentCore::MCP::ServerConfig.new(id: "  ", command: "echo") }
  end

  def test_stdio_requires_command
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", transport: :stdio, command: nil)
    end
  end

  def test_stdio_rejects_url
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", url: "https://example.com")
    end
  end

  def test_stdio_rejects_headers
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", headers: { "X-Key" => "val" })
    end
  end

  def test_stdio_rejects_headers_provider
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", headers_provider: -> { {} })
    end
  end

  def test_stdio_rejects_http_timeout_fields
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", open_timeout_s: 5)
    end

    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", read_timeout_s: 5)
    end

    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", sse_max_reconnects: 5)
    end

    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", max_response_bytes: 1000)
    end
  end

  def test_streamable_http_requires_url
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", transport: :streamable_http, url: nil)
    end
  end

  def test_streamable_http_rejects_command
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", transport: :streamable_http, url: "https://example.com", command: "echo")
    end
  end

  def test_streamable_http_rejects_args
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", transport: :streamable_http, url: "https://example.com", args: ["--flag"])
    end
  end

  def test_streamable_http_rejects_env
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", transport: :streamable_http, url: "https://example.com", env: { "FOO" => "bar" })
    end
  end

  def test_streamable_http_rejects_chdir
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", transport: :streamable_http, url: "https://example.com", chdir: "/tmp")
    end
  end

  def test_unsupported_transport
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", transport: :websocket, command: "echo")
    end
  end

  def test_transport_defaults_to_stdio
    config = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo")
    assert_equal :stdio, config.transport
  end

  def test_transport_accepts_string
    config = AgentCore::MCP::ServerConfig.new(id: "test", transport: "stdio", command: "echo")
    assert_equal :stdio, config.transport
  end

  def test_transport_accepts_streamable_http_dash
    config = AgentCore::MCP::ServerConfig.new(id: "test", transport: "streamable-http", url: "https://example.com")
    assert_equal :streamable_http, config.transport
  end

  def test_timeout_s_positive
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", timeout_s: 0)
    end

    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", timeout_s: -1)
    end
  end

  def test_env_normalization
    config = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", env: { FOO: "bar", "NUM" => 42 })
    assert_equal({ "FOO" => "bar", "NUM" => "42" }, config.env)
  end

  def test_args_normalization
    config = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", args: [:hello, 42])
    assert_equal ["hello", "42"], config.args
  end

  def test_capabilities_default_empty_hash
    config = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo")
    assert_equal({}, config.capabilities)
  end

  def test_client_info_non_hash_becomes_nil
    config = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", client_info: "not a hash")
    assert_nil config.client_info
  end

  def test_callable_validation
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.new(id: "test", command: "echo", on_stdout_line: "not callable")
    end
  end

  def test_coerce_from_hash
    config = AgentCore::MCP::ServerConfig.coerce(id: "test", command: "echo")

    assert_instance_of AgentCore::MCP::ServerConfig, config
    assert_equal "test", config.id
  end

  def test_coerce_passthrough
    original = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo")
    result = AgentCore::MCP::ServerConfig.coerce(original)

    assert_same original, result
  end

  def test_coerce_rejects_non_hash
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.coerce("not a hash")
    end
  end

  def test_coerce_rejects_string_keys
    assert_raises(ArgumentError) do
      AgentCore::MCP::ServerConfig.coerce("id" => "test", "command" => "echo")
    end
  end

  def test_data_define_frozen
    config = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo")
    assert config.frozen?
  end

  def test_data_define_equality
    a = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo")
    b = AgentCore::MCP::ServerConfig.new(id: "test", command: "echo")

    assert_equal a, b
  end
end
