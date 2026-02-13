# frozen_string_literal: true

class TestLLMModelConnection
  def self.call(llm_model:, client: nil)
    new(llm_model: llm_model, client: client).call
  end

  def initialize(llm_model:, client:)
    @llm_model = llm_model
    @client = client
  end

  def call
    response =
      client.chat_completions(
        model: llm_model.model,
        messages: [{ role: "user", content: "ping" }],
        max_tokens: 1,
        temperature: 0,
      )

    if response.respond_to?(:success?) && response.success? == true
      llm_model.update!(connection_tested_at: Time.current)
      Result.success(value: llm_model)
    else
      llm_model.update!(connection_tested_at: nil)
      Result.failure(errors: ["connection test failed"], code: "CONNECTION_FAILED", value: llm_model)
    end
  rescue StandardError => e
    llm_model.update!(connection_tested_at: nil)
    Result.failure(errors: [e.message], code: "CONNECTION_FAILED", value: llm_model)
  end

  private

  attr_reader :llm_model, :client

  def client
    @client ||= llm_model.llm_provider.build_simple_inference_client
  end
end
