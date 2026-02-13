# frozen_string_literal: true

module AgentCore
  module Resources
    module Memory
      # Abstract base class for agent memory (long-term context / RAG).
      #
      # Memory provides the agent with relevant context from past interactions,
      # documents, or other knowledge sources. The app implements a concrete
      # adapter backed by vector search (pgvector, sqlite-vec, etc.).
      class Base
        # Search memory for entries relevant to the query.
        #
        # @param query [String] Search query
        # @param limit [Integer] Maximum results to return
        # @param metadata_filter [Hash, nil] Optional metadata filters
        # @return [Array<Entry>]
        def search(query:, limit: 5, metadata_filter: nil)
          raise AgentCore::NotImplementedError, "#{self.class}#search must be implemented"
        end

        # Store a new memory entry.
        #
        # @param content [String] The content to remember
        # @param metadata [Hash] Associated metadata (tags, source, timestamp, etc.)
        # @return [Entry] The stored entry
        def store(content:, metadata: {})
          raise AgentCore::NotImplementedError, "#{self.class}#store must be implemented"
        end

        # Remove a memory entry by ID.
        #
        # @param id [String] Entry identifier
        # @return [Boolean] Whether the entry was found and removed
        def forget(id:)
          raise AgentCore::NotImplementedError, "#{self.class}#forget must be implemented"
        end

        # Return all stored entries (use with caution on large stores).
        # @return [Array<Entry>]
        def all
          raise AgentCore::NotImplementedError, "#{self.class}#all must be implemented"
        end

        # Number of entries in the store.
        # @return [Integer]
        def size
          raise AgentCore::NotImplementedError, "#{self.class}#size must be implemented"
        end

        # Clear all memory entries.
        # @return [self]
        def clear
          raise AgentCore::NotImplementedError, "#{self.class}#clear must be implemented"
        end
      end

      # A single memory entry.
      class Entry
        attr_reader :id, :content, :metadata, :score

        # @param id [String] Unique identifier
        # @param content [String] The remembered content
        # @param metadata [Hash] Associated metadata
        # @param score [Float, nil] Relevance score (from search)
        def initialize(id:, content:, metadata: {}, score: nil)
          @id = id
          @content = content
          @metadata = metadata.freeze
          @score = score
        end

        def to_h
          h = { id: id, content: content, metadata: metadata }
          h[:score] = score if score
          h
        end
      end
    end
  end
end
