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
          @content = Array(content).freeze
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
