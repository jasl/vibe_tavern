# frozen_string_literal: true

module AgentCore
  module Resources
    module Provider
      # Abstract base class for LLM providers.
      #
      # The app implements a concrete provider wrapping its HTTP client
      # (e.g., ruby_llm, faraday, httpx). AgentCore never makes network
      # requests directly.
      #
      # @example Implementing a provider
      #   class AnthropicProvider < AgentCore::Resources::Provider::Base
      #     def initialize(api_key:, base_url: "https://api.anthropic.com")
      #       @client = HttpClient.new(api_key: api_key, base_url: base_url)
      #     end
      #
      #     def chat(messages:, model:, tools: nil, stream: false, **options)
      #       if stream
      #         stream_chat(messages: messages, model: model, tools: tools, **options)
      #       else
      #         sync_chat(messages: messages, model: model, tools: tools, **options)
      #       end
      #     end
      #   end
      class Base
        # Send a chat completion request to the LLM.
        #
        # @param messages [Array<Message>] Conversation messages
        # @param model [String] Model identifier (e.g., "claude-sonnet-4-5-20250929")
        # @param tools [Array<Hash>, nil] Tool definitions in provider format
        # @param stream [Boolean] Whether to stream the response
        # @param options [Hash] Additional provider-specific options
        #   (temperature, max_tokens, top_p, stop_sequences, etc.)
        #
        # @return [Response] when stream: false
        # @return [Enumerator<StreamEvent>] when stream: true
        def chat(messages:, model:, tools: nil, stream: false, **options)
          raise AgentCore::NotImplementedError, "#{self.class}#chat must be implemented"
        end

        # Return the provider name.
        # @return [String]
        def name
          raise AgentCore::NotImplementedError, "#{self.class}#name must be implemented"
        end

        # Return available models for this provider.
        # Override in subclasses to list supported models.
        # @return [Array<Hash>] Each hash: { id: "model-id", name: "Display Name" }
        def models
          []
        end
      end
    end
  end
end
