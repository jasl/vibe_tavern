# frozen_string_literal: true

module AgentCore
  module Resources
    module ChatHistory
      # Abstract base class for chat history storage.
      #
      # Provides an Enumerable interface yielding Messages in chronological order.
      # Concrete implementations handle persistence (in-memory, database, file, etc.).
      #
      # The app implements a concrete adapter for its storage backend.
      class Base
        include Enumerable

        # Append a message to the history.
        # @param message [Message] The message to append
        # @return [self]
        def append(message)
          raise AgentCore::NotImplementedError, "#{self.class}#append must be implemented"
        end

        # Iterate over messages in chronological order.
        # @yield [Message]
        # @return [Enumerator] if no block given
        def each(&block)
          raise AgentCore::NotImplementedError, "#{self.class}#each must be implemented"
        end

        # Number of messages in the history.
        # @return [Integer]
        def size
          raise AgentCore::NotImplementedError, "#{self.class}#size must be implemented"
        end

        # Remove all messages.
        # @return [self]
        def clear
          raise AgentCore::NotImplementedError, "#{self.class}#clear must be implemented"
        end

        # Return the last n messages.
        # @param n [Integer]
        # @return [Array<Message>]
        def last(n = 1)
          to_a.last(n)
        end

        # Whether the history is empty.
        def empty?
          size == 0
        end

        # Append multiple messages.
        # @param messages [Array<Message>]
        # @return [self]
        def append_many(messages)
          messages.each { |msg| append(msg) }
          self
        end

        # Convenience: append operator.
        def <<(message)
          append(message)
        end
      end

      # Normalize various inputs into a ChatHistory adapter.
      #
      # @param input [nil, Array, Base, Enumerable]
      # @return [Base]
      def self.wrap(input)
        case input
        when nil
          InMemory.new
        when Base
          input
        when Array
          InMemory.new(input)
        else
          if input.respond_to?(:each)
            InMemory.new(input.to_a)
          else
            raise ArgumentError, "Unsupported chat history: #{input.class}. " \
                                 "Expected nil, Array, Enumerable, or ChatHistory::Base."
          end
        end
      end
    end
  end
end
