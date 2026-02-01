# frozen_string_literal: true

module TavernKit
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
    end

    attr_reader :max_size

    def size = @store.size

    def key?(key) = @store.key?(key)

    def clear
      @store.clear
    end

    def get(key)
      return nil unless @store.key?(key)

      value = @store.delete(key)
      @store[key] = value
      value
    end

    def set(key, value)
      @store.delete(key)
      @store[key] = value

      @store.shift while @store.size > @max_size
      value
    end

    def fetch(key)
      return get(key) if @store.key?(key)
      raise KeyError, "key not found: #{key.inspect}" unless block_given?

      set(key, yield)
    end
  end
end
