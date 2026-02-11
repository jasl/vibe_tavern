# frozen_string_literal: true

require "json"
require "timeout"
require "socket"

module SimpleInference
  module Protocols
    # Shared protocol helpers (HTTP requests, error handling, JSON parsing).
    #
    # Protocol implementations are responsible for:
    # - building provider-specific URLs/headers/bodies
    # - mapping provider request/response shapes to the app-facing contract
    #
    # This base class provides consistent HTTP error semantics across protocols.
    class Base
      attr_reader :config, :adapter

      def initialize(options = {})
        @config = Config.new(options || {})
        @adapter = @config.adapter || HTTPAdapters::Default.new

        unless @adapter.is_a?(HTTPAdapter)
          raise Errors::ConfigurationError,
                "adapter must be an instance of SimpleInference::HTTPAdapter (got #{@adapter.class})"
        end
      end

      private

      def request_json(method:, url:, headers:, body:, expect_json:, raise_on_http_error:)
        headers = (headers || {}).merge("Content-Type" => "application/json")
        payload = body.nil? ? nil : JSON.generate(body)

        request_env = {
          method: method,
          url: url,
          headers: headers,
          body: payload,
          timeout: config.timeout,
          open_timeout: config.open_timeout,
          read_timeout: config.read_timeout,
        }

        handle_response(
          request_env,
          expect_json: expect_json,
          raise_on_http_error: raise_on_http_error,
        )
      end

      def validate_url!(url)
        raw = url.to_s.strip
        raise Errors::ConfigurationError, "base_url is required" if raw.empty?
        return if raw.include?("://")

        raise Errors::ConfigurationError, "base_url must include a scheme (http:// or https://)"
      end

      def handle_response(request_env, expect_json:, raise_on_http_error:)
        validate_url!(request_env[:url])

        raw_response = @adapter.call(request_env)

        status = raw_response[:status].to_i
        headers = (raw_response[:headers] || {}).transform_keys { |k| k.to_s.downcase }
        body = raw_response[:body]
        body_str = body.nil? ? "" : body.to_s

        should_parse_json =
          if expect_json.nil?
            content_type = headers["content-type"]
            content_type && content_type.include?("json")
          else
            expect_json
          end

        parsed_body =
          if should_parse_json
            begin
              parse_json(body_str)
            rescue Errors::DecodeError
              # Prefer HTTPError over DecodeError for non-2xx responses.
              status >= 200 && status < 300 ? raise : body_str
            end
          else
            body_str
          end

        response = Response.new(status: status, headers: headers, body: parsed_body, raw_body: body_str)
        maybe_raise_http_error(response: response, raise_on_http_error: raise_on_http_error)
        response
      rescue Timeout::Error => e
        raise Errors::TimeoutError, e.message
      rescue SocketError, SystemCallError => e
        raise Errors::ConnectionError, e.message
      end

      def parse_json(body)
        return nil if body.nil? || body.empty?

        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Errors::DecodeError, "Failed to parse JSON response: #{e.message}"
      end

      def raise_on_http_error?(raise_on_http_error)
        raise_on_http_error.nil? ? config.raise_on_error : !!raise_on_http_error
      end

      def http_error_message(status, body_str, parsed_body: nil)
        message = "HTTP #{status}"

        error_body =
          if parsed_body.is_a?(Hash)
            parsed_body
          else
            begin
              JSON.parse(body_str)
            rescue JSON::ParserError
              nil
            end
          end

        return message unless error_body.is_a?(Hash)

        error_field = error_body["error"]
        if error_field.is_a?(Hash)
          error_field["message"] || error_body["message"] || message
        else
          error_field || error_body["message"] || message
        end
      end

      def maybe_raise_http_error(response:, raise_on_http_error:, ignore_streaming_unsupported: false)
        return unless raise_on_http_error?(raise_on_http_error)
        return if response.success?

        # Some protocols synthesize streaming behavior on top of non-streaming
        # responses; let the protocol opt out of raising for that known case.
        if ignore_streaming_unsupported && respond_to?(:streaming_unsupported_error?, true) &&
            streaming_unsupported_error?(response.status, response.body)
          return
        end

        raise Errors::HTTPError.new(
          http_error_message(response.status, response.raw_body.to_s, parsed_body: response.body),
          response: response,
        )
      end
    end
  end
end
