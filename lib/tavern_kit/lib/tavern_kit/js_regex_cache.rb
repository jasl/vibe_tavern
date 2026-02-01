# frozen_string_literal: true

require "js_regex_to_ruby"

module TavernKit
  # Bounded cache for JS-style regex literals, e.g. "/h.llo/i".
  #
  # Used by both the SillyTavern and RisuAI lore engines.
  class JsRegexCache
    DEFAULT_MAX_SIZE = 512

    def initialize(max_size: DEFAULT_MAX_SIZE, literal_only: true)
      @cache = TavernKit::LRUCache.new(max_size: max_size)
      @literal_only = literal_only == true
    end

    def fetch(value)
      v = value.to_s
      return nil unless v.start_with?("/")

      @cache.fetch(v) { ::JsRegexToRuby.try_convert(v, literal_only: @literal_only) }
    end

    def clear = @cache.clear
    def size = @cache.size
  end
end
