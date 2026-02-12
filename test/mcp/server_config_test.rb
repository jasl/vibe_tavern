# frozen_string_literal: true

require_relative "test_helper"

class MCPServerConfigTest < Minitest::Test
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

    assert_equal %w[1 two], cfg.args
    assert_equal({ "PATH" => "/bin", "foo" => nil }, cfg.env)
    assert_nil cfg.chdir
    assert_equal TavernKit::VibeTavern::Tools::MCP::DEFAULT_PROTOCOL_VERSION, cfg.protocol_version
    assert_equal({}, cfg.capabilities)
    assert_nil cfg.client_info
    assert_equal TavernKit::VibeTavern::Tools::MCP::DEFAULT_TIMEOUT_S, cfg.timeout_s
  end
end
