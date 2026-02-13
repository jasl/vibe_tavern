# frozen_string_literal: true

require_relative "test_helper"

class MCPServerConfigTest < Minitest::Test
  def test_stdio_transport_requires_command
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(id: "x")
    end
  end

  def test_streamable_http_transport_requires_url
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(id: "x", transport: :streamable_http)
    end
  end

  def test_stdio_transport_rejects_http_fields
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        command: "echo",
        url: "http://example.test/mcp",
      )
    end

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        command: "echo",
        headers: { "Authorization" => "Bearer token" },
      )
    end

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        command: "echo",
        max_response_bytes: 123,
      )
    end
  end

  def test_streamable_http_transport_rejects_stdio_fields
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        transport: :streamable_http,
        url: "http://example.test/mcp",
        command: "echo",
      )
    end

    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        transport: :streamable_http,
        url: "http://example.test/mcp",
        args: ["--foo"],
      )
    end
  end

  def test_streamable_http_transport_normalizes_headers_and_timeouts
    cfg =
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        transport: :streamable_http,
        url: "http://example.test/mcp",
        headers: { Authorization: "Bearer token", nil => "ignored", " " => "ignored", foo: nil },
        timeout_s: 5,
        open_timeout_s: 2,
        read_timeout_s: 3,
        sse_max_reconnects: 7,
        max_response_bytes: 123,
      )

    assert_equal :streamable_http, cfg.transport
    assert_equal "http://example.test/mcp", cfg.url
    assert_equal({ "Authorization" => "Bearer token" }, cfg.headers)
    assert_equal 5.0, cfg.timeout_s
    assert_equal 2.0, cfg.open_timeout_s
    assert_equal 3.0, cfg.read_timeout_s
    assert_equal 7, cfg.sse_max_reconnects
    assert_equal 123, cfg.max_response_bytes

    assert_nil cfg.command
    assert_equal [], cfg.args
    assert_equal({}, cfg.env)
    assert_nil cfg.chdir
  end

  def test_coerce_returns_same_instance
    cfg =
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        command: "echo",
      )

    assert_same cfg, TavernKit::VibeTavern::Tools::MCP::ServerConfig.coerce(cfg)
  end

  def test_coerce_requires_hash_or_server_config
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.coerce("nope")
    end
  end

  def test_coerce_requires_symbol_keys
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.coerce(
        {
          "id" => "x",
          "command" => "echo",
        },
      )
    end
  end

  def test_env_must_be_hash
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        command: "echo",
        env: "NOPE",
      )
    end
  end

  def test_timeout_s_must_be_positive
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        command: "echo",
        timeout_s: 0,
      )
    end
  end

  def test_open_timeout_s_must_be_positive
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        transport: :streamable_http,
        url: "http://example.test/mcp",
        open_timeout_s: 0,
      )
    end
  end

  def test_read_timeout_s_must_be_positive
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        transport: :streamable_http,
        url: "http://example.test/mcp",
        read_timeout_s: 0,
      )
    end
  end

  def test_max_response_bytes_must_be_positive
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        transport: :streamable_http,
        url: "http://example.test/mcp",
        max_response_bytes: 0,
      )
    end
  end

  def test_headers_must_be_hash
    assert_raises(ArgumentError) do
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        transport: :streamable_http,
        url: "http://example.test/mcp",
        headers: "NOPE",
      )
    end
  end

  def test_defaults_and_normalization
    cfg =
      TavernKit::VibeTavern::Tools::MCP::ServerConfig.new(
        id: "x",
        command: "echo",
        args: [1, :two],
        env: { PATH: "/bin", nil => "ignored", " " => "ignored", foo: nil },
        chdir: " ",
        protocol_version: " ",
        capabilities: "nope",
        client_info: "nope",
      )

    assert_equal :stdio, cfg.transport
    assert_equal %w[1 two], cfg.args
    assert_equal({ "PATH" => "/bin", "foo" => nil }, cfg.env)
    assert_nil cfg.chdir
    assert_equal TavernKit::VibeTavern::Tools::MCP::DEFAULT_PROTOCOL_VERSION, cfg.protocol_version
    assert_equal({}, cfg.capabilities)
    assert_nil cfg.client_info
    assert_equal TavernKit::VibeTavern::Tools::MCP::DEFAULT_TIMEOUT_S, cfg.timeout_s
  end
end
