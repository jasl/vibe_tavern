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
        # Default token estimates for non-text content blocks.
        # Conservative values — override in subclass or app-injected counter
        # for more precise estimates (e.g., based on image dimensions).
        DEFAULT_IMAGE_TOKENS = 1_600    # Anthropic: ~1,600 for ≤384px image
        DEFAULT_DOCUMENT_TOKENS = 2_000 # ~1 page PDF
        DEFAULT_AUDIO_TOKENS = 1_000    # ~30s audio

        # Count tokens in a text string.
        #
        # @param text [String] The text to count
        # @return [Integer] Estimated token count
        def count_text(text)
          raise AgentCore::NotImplementedError, "#{self.class}#count_text must be implemented"
        end

        # Count tokens across an array of messages.
        #
        # Handles both simple string content and array content blocks
        # (text, image, document, audio). Non-text blocks use fixed
        # estimates that can be overridden by subclasses.
        #
        # @param messages [Array<Message>] Messages to count
        # @param per_message_overhead [Integer] Fixed token overhead per message
        #   (accounts for role tags, separators, etc.)
        # @return [Integer]
        def count_messages(messages, per_message_overhead: 4)
          return 0 if messages.nil? || messages.empty?

          messages.sum do |msg|
            tokens = per_message_overhead
            tokens += count_message_content(msg)
            tokens
          end
        end

        # Count tokens for a single content block.
        #
        # @param block [TextContent, ImageContent, DocumentContent, AudioContent] A content block
        # @return [Integer]
        def count_content_block(block)
          case block
          when AgentCore::TextContent then count_text(block.text.to_s)
          when AgentCore::ImageContent then count_image(block)
          when AgentCore::DocumentContent then count_document(block)
          when AgentCore::AudioContent then count_audio(block)
          else 0
          end
        end

        # Estimate tokens for an image content block.
        # Override for precise per-image estimates (e.g., based on dimensions).
        #
        # @param _block [ImageContent]
        # @return [Integer]
        def count_image(_block)
          DEFAULT_IMAGE_TOKENS
        end

        # Estimate tokens for a document content block.
        # Text-based documents use text counting; binary documents use fixed estimate.
        #
        # @param block [DocumentContent]
        # @return [Integer]
        def count_document(block)
          text = block.respond_to?(:text) ? block.text : nil
          text && !text.empty? ? count_text(text) : DEFAULT_DOCUMENT_TOKENS
        end

        # Estimate tokens for an audio content block.
        # Uses transcript if available; otherwise falls back to fixed estimate.
        #
        # @param block [AudioContent]
        # @return [Integer]
        def count_audio(block)
          text = block.respond_to?(:text) ? block.text : nil
          text && !text.empty? ? count_text(text) : DEFAULT_AUDIO_TOKENS
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

        # Count tokens for a message's content, dispatching on content type.
        def count_message_content(msg)
          content = msg.respond_to?(:content) ? msg.content : nil

          case content
          when String
            count_text(content)
          when Array
            content.sum { |block| count_content_block(block) }
          when nil
            0
          else
            count_text(content.to_s)
          end
        end

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
