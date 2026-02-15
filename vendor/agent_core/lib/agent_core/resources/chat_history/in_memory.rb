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

        # Replace a message in the history by object identity.
        #
        # This is a convenience for in-memory sessions where callers may want
        # to rewrite/normalize a previously appended message (e.g., language
        # policy rewrite of the final assistant message).
        #
        # @param target [Message] The exact message object to replace
        # @param replacement [Message] The new message object
        # @return [Boolean] true if replaced, false if not found
        def replace_message(target, replacement)
          raise ArgumentError, "target is required" if target.nil?
          raise ArgumentError, "replacement is required" if replacement.nil?

          @mutex.synchronize do
            idx = @messages.rindex { |m| m.equal?(target) }
            return false unless idx

            @messages[idx] = replacement
            true
          end
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
