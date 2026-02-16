# frozen_string_literal: true

require "test_helper"

class AgentCore::Agent::BuilderTest < Minitest::Test
  def test_defaults
    builder = AgentCore::Agent::Builder.new

    assert_equal "Agent", builder.name
    assert_equal "", builder.description
    assert_equal "You are a helpful assistant.", builder.system_prompt
    assert_nil builder.model
    assert_nil builder.temperature
    assert_nil builder.max_tokens
    assert_equal 10, builder.max_turns
    assert_nil builder.context_window
    assert_equal 0, builder.reserved_output_tokens
  end

  def test_build_requires_provider
    builder = AgentCore::Agent::Builder.new

    assert_raises(AgentCore::ConfigurationError) do
      builder.build
    end
  end

  def test_build_creates_agent
    builder = AgentCore::Agent::Builder.new
    builder.provider = MockProvider.new
    builder.model = "test-model"

    agent = builder.build
    assert_instance_of AgentCore::Agent, agent
    assert_equal "Agent", agent.name
    assert_equal "test-model", agent.model
  end

  def test_build_validates_context_window
    builder = AgentCore::Agent::Builder.new
    builder.provider = MockProvider.new
    builder.context_window = -1

    assert_raises(AgentCore::ConfigurationError) { builder.build }
  end

  def test_build_validates_reserved_output_tokens
    builder = AgentCore::Agent::Builder.new
    builder.provider = MockProvider.new
    builder.reserved_output_tokens = -1

    assert_raises(AgentCore::ConfigurationError) { builder.build }
  end

  def test_build_validates_reserved_output_tokens_less_than_context_window
    builder = AgentCore::Agent::Builder.new
    builder.provider = MockProvider.new
    builder.context_window = 1000
    builder.reserved_output_tokens = 1000

    assert_raises(AgentCore::ConfigurationError) { builder.build }
  end

  def test_build_validates_token_counter_interface
    builder = AgentCore::Agent::Builder.new
    builder.provider = MockProvider.new
    builder.token_counter = Object.new # missing methods

    assert_raises(AgentCore::ConfigurationError) { builder.build }
  end

  def test_to_config
    builder = AgentCore::Agent::Builder.new
    builder.name = "MyAgent"
    builder.description = "A test agent"
    builder.system_prompt = "Be helpful"
    builder.model = "claude-sonnet"
    builder.temperature = 0.7
    builder.max_tokens = 4096
    builder.max_turns = 5

    config = builder.to_config

    assert_equal 1, config[:version]
    assert_equal "MyAgent", config[:identity][:name]
    assert_equal "A test agent", config[:identity][:description]
    assert_equal "Be helpful", config[:identity][:system_prompt]
    assert_equal "claude-sonnet", config[:llm][:model]
    assert_equal 0.7, config[:llm][:options][:temperature]
    assert_equal 4096, config[:llm][:options][:max_tokens]
    assert_equal 5, config[:execution][:max_turns]
  end

  def test_to_config_omits_nil_values
    builder = AgentCore::Agent::Builder.new
    config = builder.to_config

    refute config[:llm].key?(:model)
    refute config[:llm][:options].key?(:temperature)
    refute config[:llm][:options].key?(:max_tokens)
    refute config[:llm][:options].key?(:top_p)
    refute config[:llm][:options].key?(:stop_sequences)
  end

  def test_load_config
    builder = AgentCore::Agent::Builder.new
    builder.load_config(
      version: 1,
      identity: { name: "Loaded" },
      llm: { model: "claude-opus", options: { temperature: 0.5 } },
      execution: { max_turns: 20 },
      token_budget: { context_window: 128_000, reserved_output_tokens: 4096 },
    )

    assert_equal "Loaded", builder.name
    assert_equal "claude-opus", builder.model
    assert_equal 0.5, builder.temperature
    assert_equal 20, builder.max_turns
    assert_equal 128_000, builder.context_window
    assert_equal 4096, builder.reserved_output_tokens
  end

  def test_load_config_with_string_keys
    builder = AgentCore::Agent::Builder.new
    builder.load_config(
      "version" => 1,
      "identity" => { "name" => "StringKeys" },
      "llm" => { "model" => "test" },
    )

    assert_equal "StringKeys", builder.name
    assert_equal "test", builder.model
  end

  def test_load_config_returns_self
    builder = AgentCore::Agent::Builder.new
    result = builder.load_config(version: 1, identity: { name: "X" })
    assert_same builder, result
  end

  def test_config_roundtrip
    builder = AgentCore::Agent::Builder.new
    builder.name = "Roundtrip"
    builder.model = "claude-sonnet"
    builder.temperature = 0.8
    builder.max_turns = 15

    config = builder.to_config

    new_builder = AgentCore::Agent::Builder.new
    new_builder.load_config(config)

    assert_equal "Roundtrip", new_builder.name
    assert_equal "claude-sonnet", new_builder.model
    assert_equal 0.8, new_builder.temperature
    assert_equal 15, new_builder.max_turns
  end

  def test_to_config_supports_only_group_selection
    builder = AgentCore::Agent::Builder.new
    config = builder.to_config(only: [:identity])

    assert_equal({ version: 1, identity: builder.to_config[:identity] }, config)
  end

  def test_to_config_supports_except_group_selection
    builder = AgentCore::Agent::Builder.new
    config = builder.to_config(except: [:llm, :execution])

    assert_equal 1, config[:version]
    refute config.key?(:llm)
    refute config.key?(:execution)
    assert config.key?(:identity)
  end

  def test_llm_options
    builder = AgentCore::Agent::Builder.new
    builder.model = "test"
    builder.temperature = 0.5
    builder.max_tokens = 1024

    opts = builder.llm_options
    assert_equal "test", opts[:model]
    assert_equal 0.5, opts[:temperature]
    assert_equal 1024, opts[:max_tokens]
    refute opts.key?(:top_p)
    refute opts.key?(:stop_sequences)
  end

  def test_llm_options_empty_when_nil
    builder = AgentCore::Agent::Builder.new
    opts = builder.llm_options
    assert_equal({}, opts)
  end
end
