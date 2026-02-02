# frozen_string_literal: true

module SimpleInference
  # A lightweight wrapper for HTTP responses returned by SimpleInference.
  #
  # - `status` is an Integer HTTP status code
  # - `headers` is a Hash with downcased String keys
  # - `body` is a parsed JSON Hash/Array, a String, or nil (e.g. SSE streaming success)
  # - `raw_body` is the raw response body String (when available)
  class Response
    attr_reader :status, :headers, :body, :raw_body

    def initialize(status:, headers:, body:, raw_body: nil)
      @status = status.to_i
      @headers = (headers || {}).transform_keys { |k| k.to_s.downcase }
      @body = body
      @raw_body = raw_body
    end

    def success?
      status >= 200 && status < 300
    end

    def to_h
      { status: status, headers: headers, body: body, raw_body: raw_body }
    end
  end
end
