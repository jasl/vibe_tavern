# frozen_string_literal: true

# SimpleCov must be started before any application code is loaded
begin
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    primary_coverage :line
    add_filter "/test/"
    add_filter "/tmp/"
    # StreamableHttp requires httpx (optional dependency) — exclude from coverage.
    # It has its own unit tests for validation/struct behavior; HTTP execution
    # is not testable without the real dependency.
    add_filter "mcp/transport/streamable_http.rb"
  end
rescue LoadError
  # SimpleCov not available — skip coverage
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "agent_core"

require "minitest/autorun"

# A mock provider for testing that returns predefined responses.
class MockProvider < AgentCore::Resources::Provider::Base
  attr_reader :calls

  def initialize(responses: [])
    @responses = responses.dup
    @calls = []
  end

  def chat(messages:, model:, tools: nil, stream: false, **options)
    @calls << { messages: messages, model: model, tools: tools, stream: stream, **options }

    if stream
      response = @responses.shift || default_response
      Enumerator.new do |y|
        y << AgentCore::StreamEvent::TextDelta.new(text: response.message.text)
        y << AgentCore::StreamEvent::MessageComplete.new(message: response.message)
        y << AgentCore::StreamEvent::Done.new(stop_reason: response.stop_reason, usage: response.usage)
      end
    else
      @responses.shift || default_response
    end
  end

  def name = "mock"

  private

  def default_response
    AgentCore::Resources::Provider::Response.new(
      message: AgentCore::Message.new(role: :assistant, content: "Mock response"),
      usage: AgentCore::Resources::Provider::Usage.new(input_tokens: 10, output_tokens: 5),
      stop_reason: :end_turn
    )
  end
end
