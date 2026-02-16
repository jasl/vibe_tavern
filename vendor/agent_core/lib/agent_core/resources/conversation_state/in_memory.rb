# frozen_string_literal: true

module AgentCore
  module Resources
    module ConversationState
      # Simple in-memory conversation state store for testing.
      #
      # Thread-safe via Mutex.
      class InMemory < Base
        def initialize(state = State.new)
          @state = state
          @mutex = Mutex.new
        end

        def load
          @mutex.synchronize { @state }
        end

        def save(state)
          raise ArgumentError, "state must be a ConversationState::State" unless state.is_a?(State)

          @mutex.synchronize { @state = state }
          self
        end
      end
    end
  end
end
