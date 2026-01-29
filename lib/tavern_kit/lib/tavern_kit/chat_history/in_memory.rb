# frozen_string_literal: true

require_relative "../chat_history"

module TavernKit
  module ChatHistory
    # Simple in-memory ChatHistory implementation backed by an Array.
    class InMemory < Base
      def initialize(messages = [])
        @messages = Array(messages).map { |msg| ChatHistory.coerce_message(msg) }
      end

      def append(message)
        @messages << ChatHistory.coerce_message(message)
        self
      end

      def each(&block)
        return enum_for(:each) unless block

        @messages.each(&block)
      end

      def size = @messages.size

      def clear
        @messages.clear
        self
      end

      def last(n)
        @messages.last(n)
      end
    end
  end
end
