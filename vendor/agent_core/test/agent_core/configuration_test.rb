# frozen_string_literal: true

require "test_helper"

class AgentCore::ConfigurationTest < Minitest::Test
  def teardown
    AgentCore.reset_config!
  end

  def test_default_allow_url_media_sources
    assert_equal false, AgentCore.config.allow_url_media_sources
  end

  def test_default_allowed_media_url_schemes
    assert_nil AgentCore.config.allowed_media_url_schemes
  end

  def test_default_media_source_validator
    assert_nil AgentCore.config.media_source_validator
  end

  def test_configure_block
    AgentCore.configure do |c|
      c.allow_url_media_sources = false
      c.allowed_media_url_schemes = %w[https]
    end

    refute AgentCore.config.allow_url_media_sources
    assert_equal %w[https], AgentCore.config.allowed_media_url_schemes
  end

  def test_reset_config
    AgentCore.configure { |c| c.allow_url_media_sources = false }
    AgentCore.reset_config!

    assert_equal false, AgentCore.config.allow_url_media_sources
  end

  def test_config_is_singleton
    assert_same AgentCore.config, AgentCore.config
  end

  def test_media_source_validator_callable
    calls = []
    AgentCore.configure do |c|
      c.media_source_validator = ->(block) { calls << block; true }
    end

    assert_respond_to AgentCore.config.media_source_validator, :call
  end
end
