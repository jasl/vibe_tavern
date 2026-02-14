# frozen_string_literal: true

require "test_helper"
require "agent_core/resources/provider/simple_inference_provider"
require "simple_inference"

class AgentCore::Resources::Provider::SimpleInferenceProviderTest < Minitest::Test
  class StubAdapter < SimpleInference::HTTPAdapter
    def initialize(&handler)
      @handler = handler
      @calls = []
    end

    attr_reader :calls

    def call(request)
      @calls << request
      @handler.call(request)
    end
  end

  def test_chat_non_streaming_returns_response_and_usage
    adapter =
      StubAdapter.new do |_req|
        body = {
          "id" => "chatcmpl_1",
          "choices" => [
            {
              "index" => 0,
              "message" => { "role" => "assistant", "content" => "Hello" },
              "finish_reason" => "stop",
            },
          ],
          "usage" => { "prompt_tokens" => 3, "completion_tokens" => 2, "total_tokens" => 5 },
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    response =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        stream: false,
      )

    assert_instance_of AgentCore::Resources::Provider::Response, response
    assert_equal "Hello", response.message.text
    assert_equal :end_turn, response.stop_reason
    assert_equal 3, response.usage.input_tokens
    assert_equal 2, response.usage.output_tokens
  end

  def test_chat_non_streaming_parses_tool_calls
    adapter =
      StubAdapter.new do |_req|
        body = {
          "id" => "chatcmpl_2",
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "content" => nil,
                "tool_calls" => [
                  {
                    "id" => "call_1",
                    "type" => "function",
                    "function" => { "name" => "echo", "arguments" => "{\"text\":\"hello\"}" },
                  },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    response =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        tools: [{ name: "echo", description: "Echo", parameters: { type: "object" } }],
        stream: false,
      )

    assert_equal :tool_use, response.stop_reason
    assert response.has_tool_calls?
    assert_equal 1, response.tool_calls.size
    assert_equal "call_1", response.tool_calls.first.id
    assert_equal "echo", response.tool_calls.first.name
    assert_equal({ "text" => "hello" }, response.tool_calls.first.arguments)
    assert_nil response.tool_calls.first.arguments_parse_error
  end

  def test_chat_non_streaming_parses_tool_calls_when_tool_calls_is_a_hash
    adapter =
      StubAdapter.new do |_req|
        body = {
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "tool_calls" => {
                  "id" => "call_1",
                  "type" => "function",
                  "function" => { "name" => "echo", "arguments" => "{\"text\":\"hello\"}" },
                },
              },
              "finish_reason" => "tool_calls",
            },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    response =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        tools: [{ name: "echo", description: "Echo", parameters: { type: "object" } }],
        stream: false,
      )

    assert_equal :tool_use, response.stop_reason
    assert_equal 1, response.tool_calls.size
    assert_equal "call_1", response.tool_calls.first.id
    assert_equal "echo", response.tool_calls.first.name
    assert_equal({ "text" => "hello" }, response.tool_calls.first.arguments)
  end

  def test_chat_non_streaming_parses_tool_call_arguments_when_arguments_is_a_hash
    adapter =
      StubAdapter.new do |_req|
        body = {
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "tool_calls" => [
                  {
                    "id" => "call_1",
                    "type" => "function",
                    "function" => { "name" => "echo", "arguments" => { "text" => "hello" } },
                  },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    response =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        tools: [{ name: "echo", description: "Echo", parameters: { type: "object" } }],
        stream: false,
      )

    assert_equal({ "text" => "hello" }, response.tool_calls.first.arguments)
    assert_nil response.tool_calls.first.arguments_parse_error
  end

  def test_chat_non_streaming_normalizes_duplicate_tool_call_ids
    adapter =
      StubAdapter.new do |_req|
        body = {
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "tool_calls" => [
                  {
                    "id" => "call_1",
                    "type" => "function",
                    "function" => { "name" => "echo", "arguments" => "{\"text\":\"a\"}" },
                  },
                  {
                    "id" => "call_1",
                    "type" => "function",
                    "function" => { "name" => "echo", "arguments" => "{\"text\":\"b\"}" },
                  },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    response =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        tools: [{ name: "echo", description: "Echo", parameters: { type: "object" } }],
        stream: false,
      )

    ids = response.tool_calls.map(&:id)
    assert_equal ["call_1", "call_1__2"], ids
  end

  def test_chat_non_streaming_marks_invalid_arguments_as_parse_error
    adapter =
      StubAdapter.new do |_req|
        body = {
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "tool_calls" => [
                  { "id" => "call_1", "type" => "function", "function" => { "name" => "echo", "arguments" => "not json" } },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    response =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        tools: [{ name: "echo", description: "Echo", parameters: { type: "object" } }],
        stream: false,
      )

    tc = response.tool_calls.first
    assert_equal({}, tc.arguments)
    assert_equal :invalid_json, tc.arguments_parse_error
  end

  def test_chat_converts_generic_tools_to_openai_shape
    adapter =
      StubAdapter.new do |req|
        payload = JSON.parse(req.fetch(:body))
        tools = payload.fetch("tools")
        tool0 = tools.first

        assert_equal "function", tool0.fetch("type")
        assert_equal "echo", tool0.dig("function", "name")
        assert tool0.dig("function", "parameters").is_a?(Hash)

        body = {
          "choices" => [
            { "message" => { "role" => "assistant", "content" => "ok" }, "finish_reason" => "stop" },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    provider.chat(
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      model: "test-model",
      tools: [{ name: "echo", description: "Echo", parameters: { type: "object" } }],
      stream: false,
    )
  end

  def test_chat_sets_parallel_tool_calls_false_by_default_when_tools_present
    adapter =
      StubAdapter.new do |req|
        payload = JSON.parse(req.fetch(:body))
        assert_equal false, payload.fetch("parallel_tool_calls")

        body = {
          "choices" => [
            { "message" => { "role" => "assistant", "content" => "ok" }, "finish_reason" => "stop" },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    provider.chat(
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      model: "test-model",
      tools: [{ name: "echo", description: "Echo", parameters: { type: "object" } }],
      stream: false,
    )
  end

  def test_chat_converts_tools_omits_empty_required_arrays
    adapter =
      StubAdapter.new do |req|
        payload = JSON.parse(req.fetch(:body))
        tool0 = payload.fetch("tools").first
        params = tool0.dig("function", "parameters")

        refute params.key?("required")

        body = {
          "choices" => [
            { "message" => { "role" => "assistant", "content" => "ok" }, "finish_reason" => "stop" },
          ],
        }

        { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(body) }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    provider.chat(
      messages: [AgentCore::Message.new(role: :user, content: "hi")],
      model: "test-model",
      tools: [{
        name: "echo",
        description: "Echo",
        parameters: { type: "object", required: [] },
      }],
      stream: false,
    )
  end

  def test_chat_streaming_emits_text_and_message_complete
    sse =
      [
        "data: " + JSON.generate({
          "id" => "chatcmpl_s1",
          "object" => "chat.completion.chunk",
          "model" => "test-model",
          "choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "content" => "He" }, "finish_reason" => nil }],
        }),
        "data: " + JSON.generate({
          "id" => "chatcmpl_s1",
          "object" => "chat.completion.chunk",
          "model" => "test-model",
          "choices" => [{ "index" => 0, "delta" => { "content" => "llo" }, "finish_reason" => nil }],
        }),
        "data: " + JSON.generate({
          "id" => "chatcmpl_s1",
          "object" => "chat.completion.chunk",
          "model" => "test-model",
          "choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "stop" }],
          "usage" => { "prompt_tokens" => 3, "completion_tokens" => 2, "total_tokens" => 5 },
        }),
        "data: [DONE]",
      ].join("\n\n") + "\n\n"

    adapter =
      StubAdapter.new do |_req|
        { status: 200, headers: { "content-type" => "text/event-stream" }, body: sse }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    events =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        stream: true,
      ).to_a

    text = events.select { |e| e.is_a?(AgentCore::StreamEvent::TextDelta) }.map(&:text).join
    assert_equal "Hello", text

    complete = events.find { |e| e.is_a?(AgentCore::StreamEvent::MessageComplete) }
    refute_nil complete
    assert_equal "Hello", complete.message.text

    done = events.find { |e| e.is_a?(AgentCore::StreamEvent::Done) }
    refute_nil done
    assert_equal :end_turn, done.stop_reason
    assert_equal 5, done.usage.total_tokens
  end

  def test_chat_streaming_accumulates_tool_call_arguments
    sse =
      [
        "data: " + JSON.generate({
          "id" => "chatcmpl_s2",
          "object" => "chat.completion.chunk",
          "model" => "test-model",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "id" => "call_1",
                    "type" => "function",
                    "function" => { "name" => "echo", "arguments" => "{\"text\":\"he" },
                  },
                ],
              },
              "finish_reason" => nil,
            },
          ],
        }),
        "data: " + JSON.generate({
          "id" => "chatcmpl_s2",
          "object" => "chat.completion.chunk",
          "model" => "test-model",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  { "index" => 0, "function" => { "arguments" => "llo\"}" } },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
        }),
        "data: [DONE]",
      ].join("\n\n") + "\n\n"

    adapter =
      StubAdapter.new do |_req|
        { status: 200, headers: { "content-type" => "text/event-stream" }, body: sse }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    events =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        stream: true,
      ).to_a

    complete = events.find { |e| e.is_a?(AgentCore::StreamEvent::MessageComplete) }
    refute_nil complete

    msg = complete.message
    assert msg.has_tool_calls?
    assert_equal 1, msg.tool_calls.size
    assert_equal "call_1", msg.tool_calls.first.id
    assert_equal "echo", msg.tool_calls.first.name
    assert_equal({ "text" => "hello" }, msg.tool_calls.first.arguments)

    done = events.find { |e| e.is_a?(AgentCore::StreamEvent::Done) }
    refute_nil done
    assert_equal :tool_use, done.stop_reason
  end

  def test_chat_streaming_falls_back_to_deterministic_tool_call_ids
    sse =
      [
        "data: " + JSON.generate({
          "id" => "chatcmpl_s3",
          "object" => "chat.completion.chunk",
          "model" => "test-model",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  { "index" => 0, "type" => "function", "function" => { "name" => "echo", "arguments" => "{\"text\":\"a\"}" } },
                  { "index" => 1, "type" => "function", "function" => { "name" => "echo", "arguments" => "{\"text\":\"b\"}" } },
                ],
              },
              "finish_reason" => "tool_calls",
            },
          ],
        }),
        "data: [DONE]",
      ].join("\n\n") + "\n\n"

    adapter =
      StubAdapter.new do |_req|
        { status: 200, headers: { "content-type" => "text/event-stream" }, body: sse }
      end

    client = SimpleInference::Client.new(base_url: "http://example.com", api_key: "x", adapter: adapter)
    provider = AgentCore::Resources::Provider::SimpleInferenceProvider.new(client: client)

    events =
      provider.chat(
        messages: [AgentCore::Message.new(role: :user, content: "hi")],
        model: "test-model",
        stream: true,
      ).to_a

    complete = events.find { |e| e.is_a?(AgentCore::StreamEvent::MessageComplete) }
    refute_nil complete

    ids = complete.message.tool_calls.map(&:id)
    assert_equal ["tc_1", "tc_2"], ids
  end
end
