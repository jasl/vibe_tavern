# frozen_string_literal: true

module AgentCore
  module Contrib
    # Simple bounded LRU cache using Ruby's ordered Hash.
    #
    # - O(1) get/set
    # - Touching an entry updates recency (moves it to the end)
    # - Oldest entries are evicted when size exceeds max_size
    class LRUCache
      def initialize(max_size:)
        @max_size = Integer(max_size)
        raise ArgumentError, "max_size must be positive" if @max_size <= 0

        @store = {}
        @mutex = Mutex.new
      end

      attr_reader :max_size

      def size = @mutex.synchronize { @store.size }

      def key?(key) = @mutex.synchronize { @store.key?(key) }

      def clear
        @mutex.synchronize { @store.clear }
      end

      def get(key)
        @mutex.synchronize do
          return nil unless @store.key?(key)

          value = @store.delete(key)
          @store[key] = value
          value
        end
      end

      def set(key, value)
        @mutex.synchronize do
          @store.delete(key)
          @store[key] = value

          @store.shift while @store.size > @max_size
          value
        end
      end

      def fetch(key)
        existing = nil
        hit = false

        @mutex.synchronize do
          if @store.key?(key)
            existing = @store.delete(key)
            @store[key] = existing
            hit = true
          end
        end

        return existing if hit
        raise KeyError, "key not found: #{key.inspect}" unless block_given?

        computed = yield
        set(key, computed)
      end
    end
  end
end
