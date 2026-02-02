# frozen_string_literal: true

begin
  require "httpx"
rescue LoadError => e
  raise LoadError,
        "httpx gem is required for SimpleInference::HTTPAdapters::HTTPX (add `gem \"httpx\"`)",
        cause: e
end

# HTTPX's stream plugin expects all request objects to respond to `#stream`,
# however some internal requests (e.g. proxy CONNECT) don't include the plugin's
# RequestMethods. Add a harmless accessor at the base class level.
unless ::HTTPX::Request.method_defined?(:stream) && ::HTTPX::Request.method_defined?(:stream=)
  ::HTTPX::Request.class_eval do
    attr_accessor :stream
  end
end

module SimpleInference
  module HTTPAdapters
    # Fiber-friendly HTTP adapter built on HTTPX.
    class HTTPX < HTTPAdapter
      def initialize(timeout: nil, client: ::HTTPX)
        @timeout = timeout

        unless client == ::HTTPX || client.is_a?(::HTTPX::Session)
          raise ArgumentError,
                "client must be ::HTTPX or an instance of ::HTTPX::Session (got #{client.class})"
        end

        @client = client
        @stream_client = client.plugin(:stream)
      end

      def call(request)
        method = request.fetch(:method).to_s.downcase.to_sym
        url = request.fetch(:url)
        headers = request[:headers] || {}
        body = request[:body]

        client = @client

        # Mirror the SDK's timeout semantics:
        # - `:timeout` is the overall request deadline (maps to HTTPX `request_timeout`)
        # - `:open_timeout` and `:read_timeout` override connect/read deadlines
        timeout = request[:timeout] || @timeout
        open_timeout = request[:open_timeout] || timeout
        read_timeout = request[:read_timeout] || timeout

        timeout_opts = {}
        timeout_opts[:request_timeout] = timeout.to_f if timeout
        timeout_opts[:connect_timeout] = open_timeout.to_f if open_timeout
        timeout_opts[:read_timeout] = read_timeout.to_f if read_timeout

        unless timeout_opts.empty?
          client = client.with(timeout: timeout_opts)
        end

        response = client.request(method, url, headers: headers, body: body)

        # HTTPX may return an error response object instead of raising.
        #
        # NOTE: Some error response objects do not expose the normal response API
        # (e.g. no `#headers`), so we must handle them explicitly.
        if response.is_a?(::HTTPX::ErrorResponse)
          raise Errors::ConnectionError, (response.error&.message || "HTTPX request failed")
        end

        if response.status.to_i == 0
          raise Errors::ConnectionError, "HTTPX request failed"
        end

        response_headers = normalize_headers(response)

        {
          status: response.status.to_i,
          headers: response_headers,
          body: response.body.to_s,
        }
      rescue ::HTTPX::TimeoutError => e
        raise Errors::TimeoutError, e.message
      rescue ::HTTPX::Error, IOError, SystemCallError => e
        raise Errors::ConnectionError, e.message
      end

      def call_stream(request)
        return call(request) unless block_given?

        method = request.fetch(:method).to_s.downcase.to_sym
        url = request.fetch(:url)
        headers = request[:headers] || {}
        body = request[:body]

        # Mirror the SDK's timeout semantics:
        # - `:timeout` is the overall request deadline (maps to HTTPX `request_timeout`)
        # - `:open_timeout` and `:read_timeout` override connect/read deadlines
        timeout = request[:timeout] || @timeout
        open_timeout = request[:open_timeout] || timeout
        read_timeout = request[:read_timeout] || timeout

        # The HTTPX stream plugin defaults to `read_timeout: Infinity`; align with the
        # non-streaming defaults unless the caller explicitly overrides.
        read_timeout ||= 60

        timeout_opts = {}
        timeout_opts[:request_timeout] = timeout.to_f if timeout
        timeout_opts[:connect_timeout] = open_timeout.to_f if open_timeout
        timeout_opts[:read_timeout] = read_timeout.to_f if read_timeout

        stream_client = @stream_client
        client =
          if timeout_opts.empty?
            stream_client.with(timeout: {})
          else
            stream_client.with(timeout: timeout_opts)
          end

        streaming = nil
        response_headers = {}
        status = nil
        full_body = +"".b

        stream_response = client.request(method, url, headers: headers, body: body, stream: true)

        if stream_response.is_a?(::HTTPX::ErrorResponse)
          raise Errors::ConnectionError, (stream_response.error&.message || "HTTPX request failed")
        end

        if stream_response.status.to_i == 0
          raise Errors::ConnectionError, "HTTPX request failed"
        end

        begin
          stream_response.each do |chunk|
            status ||= stream_response.status.to_i
            response_headers = normalize_headers(stream_response) if response_headers.empty?
            streaming = streamable_sse?(status, response_headers) if streaming.nil?

            if streaming
              yield chunk
            else
              full_body << chunk.to_s
            end
          end
        rescue ::HTTPX::HTTPError => e
          # HTTPX's stream plugin raises for non-2xx. Swallow it and let the SDK
          # raise `Errors::HTTPError` based on status.
          status ||= e.response.status.to_i
          response_headers = normalize_headers(e.response) if response_headers.empty?
        end

        status ||= stream_response.status.to_i
        response_headers = normalize_headers(stream_response) if response_headers.empty?

        if streamable_sse?(status, response_headers)
          { status: status, headers: response_headers, body: nil }
        else
          { status: status, headers: response_headers, body: full_body.to_s }
        end
      rescue ::HTTPX::TimeoutError => e
        raise Errors::TimeoutError, e.message
      rescue ::HTTPX::Error, IOError, SystemCallError => e
        raise Errors::ConnectionError, e.message
      end

      private

      def normalize_headers(response)
        response.headers.to_h.each_with_object({}) do |(k, v), out|
          out[k.to_s] = v.is_a?(Array) ? v.join(", ") : v.to_s
        end
      end

      def streamable_sse?(status, headers)
        return false unless status.to_i >= 200 && status.to_i < 300

        content_type =
          headers.each_with_object({}) do |(k, v), out|
            out[k.to_s.downcase] = v
          end["content-type"].to_s

        content_type.include?("text/event-stream")
      end
    end
  end
end
