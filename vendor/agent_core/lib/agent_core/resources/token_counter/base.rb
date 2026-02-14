# frozen_string_literal: true

module AgentCore
  module Resources
    module TokenCounter
      # Abstract base class for token counting.
      #
      # The app implements a concrete counter (e.g., tiktoken, HuggingFace
      # tokenizers). AgentCore ships only a heuristic fallback.
      #
      # @example Implementing a counter
      #   class TiktokenCounter < AgentCore::Resources::TokenCounter::Base
      #     def count_text(text)
      #       @encoding.encode(text).length
      #     end
      #   end
      class Base
        # Count tokens in a text string.
        #
        # @param text [String] The text to count
        # @return [Integer] Estimated token count
        def count_text(text)
          raise AgentCore::NotImplementedError, "#{self.class}#count_text must be implemented"
        end

        # Count tokens across an array of messages.
        #
        # Default implementation sums count_text for each message's text
        # content plus a per-message overhead (role, metadata framing).
        #
        # @param messages [Array<Message>] Messages to count
        # @param per_message_overhead [Integer] Fixed token overhead per message
        #   (accounts for role tags, separators, etc.)
        # @return [Integer]
        def count_messages(messages, per_message_overhead: 4)
          return 0 if messages.nil? || messages.empty?

          messages.sum do |msg|
            text = msg.respond_to?(:text) ? msg.text.to_s : msg.to_s
            count_text(text) + per_message_overhead
          end
        end

        # Count tokens for tool definitions.
        #
        # Default implementation serializes tool definitions to JSON and
        # counts the resulting text. This is an approximation — providers
        # may tokenize tool schemas differently.
        #
        # @param tools [Array<Hash>] Tool definitions
        # @return [Integer]
        def count_tools(tools)
          return 0 if tools.nil? || tools.empty?

          json = tools.map { |t| serialize_tool(t) }.join
          count_text(json)
        end

        private

        def serialize_tool(tool)
          if tool.respond_to?(:to_json)
            tool.to_json
          else
            tool.to_s
          end
        end
      end
    end
  end
end
