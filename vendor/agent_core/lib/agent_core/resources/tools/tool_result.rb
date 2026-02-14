# frozen_string_literal: true

module AgentCore
  module Resources
    module Tools
      # The result of executing a tool.
      #
      # Contains content blocks (text, images, etc.) and error status.
      # Normalized across all tool sources (native, MCP, skills).
      class ToolResult
        attr_reader :content, :is_error, :metadata

        # @param content [Array<Hash>] Content blocks
        #   Each block: { type: "text", text: "..." } or { type: "image", ... }
        # @param is_error [Boolean] Whether this result represents an error
        # @param metadata [Hash] Optional metadata (timing, byte counts, etc.)
        def initialize(content:, is_error: false, metadata: {})
          normalized = Array(content).map do |block|
            if block.is_a?(Hash)
              block
            else
              { type: "text", text: block.to_s }
            end
          end

          @content = normalized.map(&:freeze).freeze
          @is_error = is_error
          @metadata = (metadata || {}).freeze
        end

        def error? = is_error

        # Convenience: get text content as a single string.
        def text
          content.filter_map { |block|
            block[:text] || block["text"] if block[:type]&.to_s == "text" || block["type"]&.to_s == "text"
          }.join("\n")
        end

        # Whether this result contains non-text content blocks (images, documents, etc.).
        def has_non_text_content?
          content.any? { |block|
            block_type = (block[:type] || block["type"])&.to_s
            block_type && block_type != "text"
          }
        end

        # Convert content hash blocks to ContentBlock objects.
        #
        # Used by the Runner to build Messages with proper content blocks
        # when tool results include images or other media.
        #
        # @return [Array<ContentBlock>] Array of typed content block objects
        def to_content_blocks
          content.map { |block| AgentCore::ContentBlock.from_h(block) }
        end

        def to_h
          { content: content, is_error: is_error, metadata: metadata }
        end

        # Build a successful text result.
        def self.success(text:, metadata: {})
          new(
            content: [{ type: "text", text: text }],
            is_error: false,
            metadata: metadata
          )
        end

        # Build an error result.
        def self.error(text:, metadata: {})
          new(
            content: [{ type: "text", text: text }],
            is_error: true,
            metadata: metadata
          )
        end

        # Build a result with multiple content blocks.
        def self.with_content(blocks, is_error: false, metadata: {})
          new(content: blocks, is_error: is_error, metadata: metadata)
        end
      end
    end
  end
end
