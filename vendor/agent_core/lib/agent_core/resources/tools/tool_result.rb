# frozen_string_literal: true

module AgentCore
  module Resources
    module Tools
      # The result of executing a tool.
      #
      # Contains content blocks (text, images, etc.) and error status.
      # Normalized across all tool sources (native, MCP, skills).
      class ToolResult
        attr_reader :content, :error, :metadata

        # @param content [Array<Hash>] Content blocks
        #   Each block: { type: :text, text: "..." } or { type: :image, ... }
        # @param error [Boolean] Whether this result represents an error
        # @param metadata [Hash] Optional metadata (timing, byte counts, etc.)
        def initialize(content:, error: false, metadata: {})
          normalized = Array(content).map do |block|
            normalize_block(block)
          end

          @content = normalized.map(&:freeze).freeze
          @error = !!error
          @metadata = (metadata || {}).freeze
        end

        def error? = error

        # Convenience: get text content as a single string.
        def text
          content.filter_map { |block|
            block[:text] if block[:type] == :text
          }.join("\n")
        end

        # Whether this result contains non-text content blocks (images, documents, etc.).
        def has_non_text_content?
          content.any? { |block|
            block[:type] && block[:type] != :text
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
          { content: content, error: error, metadata: metadata }
        end

        # Build a ToolResult from a Hash (symbol or string keys) or JSON String.
        #
        # Intended for app-side persistence round-trips and job queues.
        #
        # @param value [Hash, String]
        # @return [ToolResult]
        def self.from_h(value)
          h =
            case value
            when String
              begin
                require "json"
                JSON.parse(value)
              rescue JSON::ParserError => e
                raise ArgumentError, "tool result is not valid JSON: #{e.message}"
              end
            when Hash
              value
            else
              raise ArgumentError, "tool result must be a Hash or JSON String (got #{value.class})"
            end

          raise ArgumentError, "tool result must be a Hash" unless h.is_a?(Hash)

          content = h.fetch("content", h.fetch(:content, nil))
          raise ArgumentError, "tool result content must be an Array" unless content.is_a?(Array)

          error = h.fetch("error", h.fetch(:error, false))

          metadata = h.fetch("metadata", h.fetch(:metadata, {}))
          metadata = {} if metadata.nil?
          raise ArgumentError, "tool result metadata must be a Hash" unless metadata.is_a?(Hash)

          metadata = AgentCore::Utils.symbolize_keys(metadata)

          new(
            content: content,
            error: !!error,
            metadata: metadata,
          )
        end

        # Build a successful text result.
        def self.success(text:, metadata: {})
          new(
            content: [{ type: :text, text: text }],
            error: false,
            metadata: metadata
          )
        end

        # Build an error result.
        def self.error(text:, metadata: {})
          new(
            content: [{ type: :text, text: text }],
            error: true,
            metadata: metadata
          )
        end

        # Build a result with multiple content blocks.
        def self.with_content(blocks, error: false, metadata: {})
          new(content: blocks, error: error, metadata: metadata)
        end

        private

        def normalize_block(block)
          unless block.is_a?(Hash)
            return { type: :text, text: block.to_s }
          end

          h = AgentCore::Utils.symbolize_keys(block)
          h = normalize_type!(h)
          h = normalize_source_type!(h)

          if h[:type].nil?
            return h.key?(:text) ? h.merge(type: :text) : { type: :text, text: block.to_s }
          end

          h
        end

        def normalize_type!(hash)
          type = hash[:type]
          return hash if type.nil?

          sym = type.is_a?(Symbol) ? type : type.to_s.to_sym
          sym == type ? hash : hash.merge(type: sym)
        end

        def normalize_source_type!(hash)
          st = hash[:source_type]
          return hash if st.nil?

          sym = st.is_a?(Symbol) ? st : st.to_s.to_sym
          sym == st ? hash : hash.merge(source_type: sym)
        end
      end
    end
  end
end
