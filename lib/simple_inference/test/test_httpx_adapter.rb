# frozen_string_literal: true

require "test_helper"

require "simple_inference/http_adapters/httpx"

class TestHTTPXAdapter < Minitest::Test
  class FakeStreamResponse
    attr_reader :status, :headers

    def initialize(status:, headers:, chunks:, raise_http_error: false)
      @status = status
      @headers = headers
      @chunks = chunks
      @raise_http_error = raise_http_error
    end

    def each
      return enum_for(__method__) unless block_given?

      @chunks.each do |chunk|
        yield chunk
      end

      raise ::HTTPX::HTTPError.new(self) if @raise_http_error
    end

    def body
      @chunks.join
    end
  end

  class FakeClient < ::HTTPX::Session
    def self.build(response)
      obj = allocate
      obj.instance_variable_set(:@response, response)
      obj
    end

    def plugin(_name)
      self
    end

    def with(timeout:)
      _timeout = timeout
      self
    end

    def request(_method, _url, headers: {}, body: nil, stream: false, **_kwargs)
      _headers = headers
      _body = body
      _stream = stream
      @response
    end
  end

  def test_error_response_raises_connection_error_instead_of_calling_headers
    skip "HTTPX::ErrorResponse not available" unless defined?(::HTTPX::ErrorResponse)

    # Simulate HTTPX returning an ErrorResponse object which does not implement
    # the normal response API (e.g. `#headers`).
    err = StandardError.new("boom")

    response = ::HTTPX::ErrorResponse.allocate
    response.define_singleton_method(:status) { 599 }
    response.define_singleton_method(:error) { err }
    adapter = SimpleInference::HTTPAdapters::HTTPX.new(client: FakeClient.build(response))

    e =
      assert_raises(SimpleInference::Errors::ConnectionError) do
        adapter.call(method: :get, url: "https://example.test")
      end

    assert_includes e.message, "boom"
  end

  def test_call_stream_yields_chunks_for_event_stream
    response =
      FakeStreamResponse.new(
        status: 200,
        headers: { "content-type" => "text/event-stream" },
        chunks: ["data: 1\n\n", "data: 2\n\n"]
      )

    adapter = SimpleInference::HTTPAdapters::HTTPX.new(client: FakeClient.build(response))

    yielded = []
    resp =
      adapter.call_stream(method: :get, url: "https://example.test") do |chunk|
        yielded << chunk
      end

    assert_equal ["data: 1\n\n", "data: 2\n\n"], yielded
    assert_equal 200, resp[:status]
    assert_equal "text/event-stream", resp.dig(:headers, "content-type")
    assert_nil resp[:body]
  end

  def test_call_stream_buffers_non_event_stream_body
    response =
      FakeStreamResponse.new(
        status: 200,
        headers: { "content-type" => "application/json" },
        chunks: ['{"ok":', "true}"]
      )

    adapter = SimpleInference::HTTPAdapters::HTTPX.new(client: FakeClient.build(response))

    yielded = []
    resp =
      adapter.call_stream(method: :get, url: "https://example.test") do |chunk|
        yielded << chunk
      end

    assert_equal [], yielded
    assert_equal 200, resp[:status]
    assert_equal '{"ok":true}', resp[:body]
  end

  def test_call_stream_swallows_http_error_and_returns_body
    response =
      FakeStreamResponse.new(
        status: 401,
        headers: { "content-type" => "application/json" },
        chunks: ['{"error":"nope"}'],
        raise_http_error: true
      )

    adapter = SimpleInference::HTTPAdapters::HTTPX.new(client: FakeClient.build(response))

    yielded = []
    resp =
      adapter.call_stream(method: :get, url: "https://example.test") do |chunk|
        yielded << chunk
      end

    assert_equal [], yielded
    assert_equal 401, resp[:status]
    assert_equal '{"error":"nope"}', resp[:body]
  end

  def test_httpx_request_has_stream_accessor
    assert ::HTTPX::Request.method_defined?(:stream)
    assert ::HTTPX::Request.method_defined?(:stream=)
  end

  def test_proxy_connect_request_inherits_stream_accessor
    begin
      require "httpx/plugins/proxy/http"
    rescue LoadError
      skip "httpx/plugins/proxy/http not available"
    end

    klass = ::HTTPX::Plugins::Proxy::HTTP::ConnectRequest
    assert klass.method_defined?(:stream)
    assert klass.method_defined?(:stream=)
  end
end
