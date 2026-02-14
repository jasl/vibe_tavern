# frozen_string_literal: true

require "test_helper"

class AgentCore::Resources::Provider::BaseTest < Minitest::Test
  def test_chat_raises_not_implemented
    provider = AgentCore::Resources::Provider::Base.new

    assert_raises(AgentCore::NotImplementedError) do
      provider.chat(messages: [], model: "test")
    end
  end

  def test_name_raises_not_implemented
    provider = AgentCore::Resources::Provider::Base.new

    assert_raises(AgentCore::NotImplementedError) do
      provider.name
    end
  end

  def test_models_default_to_empty_array
    provider = AgentCore::Resources::Provider::Base.new
    assert_equal [], provider.models
  end

  def test_subclass_can_implement
    custom = Class.new(AgentCore::Resources::Provider::Base) do
      def name
        "custom"
      end

      def chat(messages:, model:, tools: nil, stream: false, **options)
        msg = AgentCore::Message.new(role: :assistant, content: "Hello")
        AgentCore::Resources::Provider::Response.new(message: msg)
      end

      def models
        [{ id: "test-model", name: "Test Model" }]
      end
    end

    provider = custom.new
    assert_equal "custom", provider.name
    assert_equal 1, provider.models.size

    response = provider.chat(messages: [], model: "test-model")
    assert_instance_of AgentCore::Resources::Provider::Response, response
  end
end
