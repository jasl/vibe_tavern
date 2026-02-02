# frozen_string_literal: true

module SimpleInference
  # Base class for HTTP adapters.
  #
  # Concrete adapters must implement `#call` and may override `#call_stream`
  # for incremental streaming.
  class HTTPAdapter
    def call(_request)
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    # Streaming-capable request helper.
    #
    # When the response is `text/event-stream` (and 2xx), it yields raw body chunks
    # as they arrive via the given block, and returns a response hash with `body: nil`.
    #
    # For non-streaming responses, it behaves like `#call` and returns the full body.
    def call_stream(request)
      return call(request) unless block_given?

      response = call(request)

      status = response[:status].to_i
      headers = response[:headers] || {}
      content_type =
        headers.each_with_object({}) do |(k, v), out|
          out[k.to_s.downcase] = v
        end["content-type"].to_s

      if status >= 200 && status < 300 && content_type.include?("text/event-stream")
        yield response[:body].to_s
        return { status: status, headers: headers, body: nil }
      end

      response
    end
  end

  module HTTPAdapters
    autoload :Default, "simple_inference/http_adapters/default"
    autoload :HTTPX, "simple_inference/http_adapters/httpx"
  end
end
