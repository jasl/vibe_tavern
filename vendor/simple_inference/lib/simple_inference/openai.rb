# frozen_string_literal: true

module SimpleInference
  # Helpers for extracting common fields from OpenAI-compatible `chat/completions` payloads.
  #
  # These helpers accept either:
  # - A `SimpleInference::Response`, or
  # - A parsed `body` / `chunk` hash (typically from JSON.parse, with String keys)
  #
  # Providers are "OpenAI-compatible", but many differ in subtle ways:
  # - Some return `choices[0].text` instead of `choices[0].message.content`
  # - Some represent `content` as an array or structured hash
  #
  # This module normalizes those shapes so application code can stay small and predictable.
  module OpenAI
    module_function

    ChatResult =
      Struct.new(
        :content,
        :usage,
        :finish_reason,
        :logprobs,
        :response,
        keyword_init: true
      )

    # Enumerable wrapper for streaming chat responses.
    #
    # @example
    #   stream = client.chat_stream(model: "...", messages: [...], include_usage: true)
    #   stream.each { |delta| print delta }
    #   p stream.result.usage
    class ChatStream
      include Enumerable

      attr_reader :result

      def initialize(client:, model:, messages:, include_usage:, request_logprobs:, top_logprobs:, params:)
        @client = client
        @model = model
        @messages = messages
        @include_usage = include_usage
        @request_logprobs = request_logprobs
        @top_logprobs = top_logprobs
        @params = params
        @started = false
        @result = nil
      end

      def each
        return enum_for(:each) unless block_given?
        raise Errors::ConfigurationError, "ChatStream can only be consumed once" if @started

        @started = true
        @result =
          @client.chat(
            model: @model,
            messages: @messages,
            stream: true,
            include_usage: @include_usage,
            request_logprobs: @request_logprobs,
            top_logprobs: @top_logprobs,
            **(@params || {})
          ) { |delta| yield delta }
      end
    end

    # Extract assistant content from a non-streaming chat completion.
    #
    # @param response_or_body [Hash] SimpleInference response hash or parsed body hash
    # @return [String, nil]
    def chat_completion_content(response_or_body)
      body = unwrap_body(response_or_body)
      choice = first_choice(body)
      return nil unless choice

      raw =
        choice.dig("message", "content") ||
          choice["text"]

      normalize_content(raw)
    end

    # Extract finish_reason from a non-streaming chat completion.
    #
    # @param response_or_body [Hash] SimpleInference response hash or parsed body hash
    # @return [String, nil]
    def chat_completion_finish_reason(response_or_body)
      body = unwrap_body(response_or_body)
      first_choice(body)&.[]("finish_reason")
    end

    # Extract usage from a chat completion response or a final streaming chunk.
    #
    # @param response_or_body [Hash] SimpleInference response hash, body hash, or chunk hash
    # @return [Hash, nil] symbol-keyed usage hash
    def chat_completion_usage(response_or_body)
      body = unwrap_body(response_or_body)
      usage = body.is_a?(Hash) ? body["usage"] : nil
      return nil unless usage.is_a?(Hash)

      {
        prompt_tokens: usage["prompt_tokens"],
        completion_tokens: usage["completion_tokens"],
        total_tokens: usage["total_tokens"],
      }.compact
    end

    # Extract logprobs (if present) from a non-streaming chat completion.
    #
    # @param response_or_body [Hash] SimpleInference response hash or parsed body hash
    # @return [Array<Hash>, nil]
    def chat_completion_logprobs(response_or_body)
      body = unwrap_body(response_or_body)
      first_choice(body)&.dig("logprobs", "content")
    end

    # Extract delta content from a streaming `chat.completion.chunk`.
    #
    # @param chunk [Hash] parsed streaming event hash
    # @return [String, nil]
    def chat_completion_chunk_delta(chunk)
      chunk = unwrap_body(chunk)
      return nil unless chunk.is_a?(Hash)

      raw = chunk.dig("choices", 0, "delta", "content")
      normalize_content(raw)
    end

    # Normalize `content` shapes into a simple String.
    #
    # Supports strings, arrays of parts, and part hashes.
    #
    # @param value [Object]
    # @return [String, nil]
    def normalize_content(value)
      case value
      when String
        value
      when Array
        value.map { |part| normalize_content(part) }.join
      when Hash
        value["text"] ||
          value["content"] ||
          value.to_s
      when nil
        nil
      else
        value.to_s
      end
    end

    # Unwrap a full SimpleInference response into its `:body`, otherwise return the object.
    #
    # @param obj [Object]
    # @return [Object]
    def unwrap_body(obj)
      return {} unless obj
      return obj.body || {} if obj.respond_to?(:body)

      obj
    end

    def first_choice(body)
      return nil unless body.is_a?(Hash)

      choices = body["choices"]
      return nil unless choices.is_a?(Array) && !choices.empty?

      choice0 = choices[0]
      return nil unless choice0.is_a?(Hash)

      choice0
    end
    private_class_method :first_choice
  end
end
