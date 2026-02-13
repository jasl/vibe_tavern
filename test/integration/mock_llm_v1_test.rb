require "test_helper"

class MockLLMV1Test < ActionDispatch::IntegrationTest
  test "GET /mock_llm/v1/models returns a mock model" do
    get "/mock_llm/v1/models"

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "list", body.fetch("object")
    assert_equal "mock", body.fetch("data").first.fetch("id")
  end

  test "POST /mock_llm/v1/chat/completions returns a chat completion" do
    post "/mock_llm/v1/chat/completions",
         params: {
           model: "mock",
           messages: [{ role: "user", content: "Hi" }],
         },
         as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "chat.completion", body.fetch("object")

    choice = body.fetch("choices").first
    assert_equal "assistant", choice.dig("message", "role")
    assert choice.dig("message", "content").present?

    usage = body.fetch("usage")
    assert_kind_of Integer, usage.fetch("prompt_tokens")
    assert_kind_of Integer, usage.fetch("completion_tokens")
    assert_kind_of Integer, usage.fetch("total_tokens")
  end

  test "POST /mock_llm/v1/chat/completions errors when model is missing" do
    post "/mock_llm/v1/chat/completions",
         params: {
           messages: [{ role: "user", content: "Hi" }],
         },
         as: :json

    assert_response :bad_request

    body = JSON.parse(response.body)
    assert_equal "invalid_request_error", body.dig("error", "type")
    assert_equal "model is required", body.dig("error", "message")
  end

  test "POST /mock_llm/v1/chat/completions errors when messages is empty" do
    post "/mock_llm/v1/chat/completions",
         params: {
           model: "mock",
           messages: [],
         },
         as: :json

    assert_response :bad_request

    body = JSON.parse(response.body)
    assert_equal "invalid_request_error", body.dig("error", "type")
    assert_equal "messages must be a non-empty array", body.dig("error", "message")
  end

  test "POST /mock_llm/v1/chat/completions errors on invalid JSON body" do
    post "/mock_llm/v1/chat/completions",
         params: "{",
         headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request

    body = JSON.parse(response.body)
    assert_equal "invalid_request_error", body.dig("error", "type")
    assert_equal "invalid JSON body", body.dig("error", "message")
  end

  test "POST /mock_llm/v1/chat/completions supports SSE streaming with usage" do
    post "/mock_llm/v1/chat/completions",
         params: {
           model: "mock",
           messages: [{ role: "user", content: "Hi" }],
           stream: true,
           stream_options: { include_usage: true },
         },
         as: :json

    assert_response :success
    assert_includes response.content_type, "text/event-stream"
    assert_includes response.body, "data: [DONE]"

    events = parse_sse_events(response.body)
    assert events.any? { |e| e.fetch("object") == "chat.completion.chunk" }
    assert events.last.key?("usage")
  end

  private

  def parse_sse_events(body)
    body
      .split("\n\n")
      .filter_map do |chunk|
        line = chunk.lines.find { |l| l.start_with?("data: ") }
        next unless line

        data = line.delete_prefix("data: ").strip
        next if data == "[DONE]"

        JSON.parse(data)
      rescue JSON::ParserError
        nil
      end
  end
end
