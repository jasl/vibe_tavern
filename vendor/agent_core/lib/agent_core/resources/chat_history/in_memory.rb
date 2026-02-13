# frozen_string_literal: true

module AgentCore
  module Resources
    module ChatHistory
      # Simple array-backed chat history for testing and simple use cases.
      #
      # Thread-safe via Mutex. For production use with many concurrent
      # writers, prefer a database-backed implementation.
      class InMemory < Base
        def initialize(messages = [])
          @messages = messages.dup
          @mutex = Mutex.new
        end

        def append(message)
          @mutex.synchronize { @messages << message }
          self
        end

        def each(&block)
          return enum_for(:each) unless block

          snapshot = @mutex.synchronize { @messages.dup }
          snapshot.each(&block)
        end

        def size
          @mutex.synchronize { @messages.size }
        end

        def clear
          @mutex.synchronize { @messages.clear }
          self
        end

        def last(n = 1)
          @mutex.synchronize { @messages.last(n) }
        end
      end
    end
  end
end
