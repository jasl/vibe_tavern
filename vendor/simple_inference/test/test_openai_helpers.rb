# frozen_string_literal: true

require "test_helper"

class TestOpenAIHelpers < Minitest::Test
  def test_chat_completion_content_accepts_response_object
    response = SimpleInference::Response.new(
      status: 200,
      headers: { "content-type" => "application/json" },
      body: { "choices" => [{ "message" => { "content" => "Hello" } }] }
    )

    assert_equal "Hello", SimpleInference::OpenAI.chat_completion_content(response)
  end

  def test_chat_completion_content_falls_back_to_text
    body = {
      "choices" => [
        { "text" => "Hello from text" },
      ],
    }

    assert_equal "Hello from text", SimpleInference::OpenAI.chat_completion_content(body)
  end

  def test_chat_completion_content_normalizes_structured_content
    body = {
      "choices" => [
        {
          "message" => {
            "content" => [
              { "type" => "text", "text" => "Hel" },
              { "type" => "text", "text" => "lo" },
            ],
          },
        },
      ],
    }

    assert_equal "Hello", SimpleInference::OpenAI.chat_completion_content(body)
  end

  def test_chat_completion_chunk_delta_extracts_delta_content
    chunk = {
      "choices" => [
        { "delta" => { "content" => "Hi" } },
      ],
    }

    assert_equal "Hi", SimpleInference::OpenAI.chat_completion_chunk_delta(chunk)
  end

  def test_chat_completion_usage_extracts_usage
    body = {
      "usage" => {
        "prompt_tokens" => 1,
        "completion_tokens" => 2,
        "total_tokens" => 3,
      },
    }

    assert_equal({ prompt_tokens: 1, completion_tokens: 2, total_tokens: 3 }, SimpleInference::OpenAI.chat_completion_usage(body))
  end
end
