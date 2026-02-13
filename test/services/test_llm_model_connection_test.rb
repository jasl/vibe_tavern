require "test_helper"

class TestLLMModelConnectionTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(response: nil, error: nil)
      @response = response
      @error = error
    end

    def chat_completions(**_params)
      raise @error if @error

      @response
    end
  end

  test "sets connection_tested_at on success" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1")

    response = SimpleInference::Response.new(status: 200, headers: {}, body: {}, raw_body: "{}")
    result = TestLLMModelConnection.call(llm_model: llm_model, client: FakeClient.new(response: response))

    assert result.success?
    assert llm_model.reload.connection_tested_at.present?
  end

  test "clears connection_tested_at on failure" do
    provider = LLMProvider.create!(name: "X", base_url: "http://example.test", api_prefix: "/v1", headers: {}, llm_options_defaults: {})
    llm_model = LLMModel.create!(llm_provider: provider, name: "M1", model: "m1", connection_tested_at: 1.day.ago)

    error = SimpleInference::Errors::ConnectionError.new("boom")
    result = TestLLMModelConnection.call(llm_model: llm_model, client: FakeClient.new(error: error))

    assert result.failure?
    assert_nil llm_model.reload.connection_tested_at
  end
end
