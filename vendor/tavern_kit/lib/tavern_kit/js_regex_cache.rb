# frozen_string_literal: true

require "js_regex_to_ruby"

module TavernKit
  # Bounded cache for JS-style regex literals, e.g. "/h.llo/i".
  #
  # Used by both the SillyTavern and RisuAI lore engines.
  class JsRegexCache
    DEFAULT_MAX_SIZE = 512
    DEFAULT_MAX_LITERAL_BYTES = 2048

    def initialize(max_size: DEFAULT_MAX_SIZE, literal_only: true, max_literal_bytes: DEFAULT_MAX_LITERAL_BYTES)
      @cache = TavernKit::LRUCache.new(max_size: max_size)
      @literal_only = literal_only == true
      @max_literal_bytes = Integer(max_literal_bytes)
    end

    def fetch(value)
      v = value.to_s
      return nil unless v.start_with?("/")
      return nil if @max_literal_bytes.positive? && v.bytesize > @max_literal_bytes

      @cache.fetch(v) do
        re = ::JsRegexToRuby.try_convert(v, literal_only: @literal_only)
        return nil unless re.is_a?(Regexp)
        re
      end
    rescue RegexpError
      nil
    end

    def clear = @cache.clear
    def size = @cache.size
  end
end
