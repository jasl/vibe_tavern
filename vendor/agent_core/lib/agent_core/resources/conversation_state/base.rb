# frozen_string_literal: true

module AgentCore
  module Resources
    module ConversationState
      # Serializable conversation context state managed by AgentCore.
      #
      # This is intentionally small and storage-agnostic. The host app decides how
      # to persist it (DB, file, cache, etc.).
      class State
        attr_reader :summary, :cursor, :compaction_count, :updated_at

        # @param summary [String, nil] Running conversation summary
        # @param cursor [Integer] Number of transcript messages covered by the summary
        # @param compaction_count [Integer] Number of compactions performed
        # @param updated_at [Time, nil] Optional timestamp for persistence
        def initialize(summary: nil, cursor: 0, compaction_count: 0, updated_at: nil)
          s = summary.to_s
          s = nil if s.strip.empty?
          @summary = s&.dup&.freeze

          @cursor = Integer(cursor || 0, exception: false) || 0
          @cursor = 0 if @cursor.negative?

          @compaction_count = Integer(compaction_count || 0, exception: false) || 0
          @compaction_count = 0 if @compaction_count.negative?

          @updated_at = updated_at
        end

        def to_h
          {
            summary: summary,
            cursor: cursor,
            compaction_count: compaction_count,
            updated_at: updated_at,
          }
        end

        def with(summary: self.summary, cursor: self.cursor, compaction_count: self.compaction_count, updated_at: self.updated_at)
          self.class.new(
            summary: summary,
            cursor: cursor,
            compaction_count: compaction_count,
            updated_at: updated_at,
          )
        end

        def empty?
          summary.nil? && cursor.zero? && compaction_count.zero?
        end
      end

      # Abstract base class for conversation state storage.
      #
      # The app implements a concrete adapter for its storage backend.
      class Base
        # Load current state.
        # @return [State]
        def load
          raise AgentCore::NotImplementedError, "#{self.class}#load must be implemented"
        end

        # Persist state.
        # @param state [State]
        # @return [self]
        def save(state)
          raise AgentCore::NotImplementedError, "#{self.class}#save must be implemented"
        end

        # Clear all state.
        # @return [self]
        def clear
          save(State.new)
          self
        end
      end

      # Normalize various inputs into a ConversationState adapter.
      #
      # @param input [nil, Base]
      # @return [Base]
      def self.wrap(input)
        case input
        when nil
          InMemory.new
        when Base
          input
        else
          raise ArgumentError, "Unsupported conversation_state: #{input.class}. " \
                               "Expected nil or ConversationState::Base."
        end
      end
    end
  end
end
