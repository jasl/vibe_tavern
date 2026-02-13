# frozen_string_literal: true

require "securerandom"

module AgentCore
  module Resources
    module Memory
      # Simple in-memory memory store for testing.
      #
      # Uses naive substring matching for search. Production implementations
      # should use vector similarity search (pgvector, sqlite-vec, etc.).
      class InMemory < Base
        def initialize
          @entries = {}
          @mutex = Mutex.new
        end

        def search(query:, limit: 5, metadata_filter: nil)
          @mutex.synchronize do
            results = @entries.values

            # Simple substring matching (naive, for testing only)
            results = results.select { |e| e.content.downcase.include?(query.downcase) }

            # Apply metadata filter if given
            if metadata_filter
              results = results.select do |e|
                metadata_filter.all? { |k, v| e.metadata[k] == v }
              end
            end

            results.first(limit).map do |e|
              Entry.new(id: e.id, content: e.content, metadata: e.metadata, score: 1.0)
            end
          end
        end

        def store(content:, metadata: {})
          id = SecureRandom.uuid
          entry = Entry.new(id: id, content: content, metadata: metadata)
          @mutex.synchronize { @entries[id] = entry }
          entry
        end

        def forget(id:)
          @mutex.synchronize { !@entries.delete(id).nil? }
        end

        def all
          @mutex.synchronize { @entries.values.dup }
        end

        def size
          @mutex.synchronize { @entries.size }
        end

        def clear
          @mutex.synchronize { @entries.clear }
          self
        end
      end
    end
  end
end
