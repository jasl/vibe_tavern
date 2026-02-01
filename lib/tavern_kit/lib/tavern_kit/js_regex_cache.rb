# frozen_string_literal: true

require "js_regex_to_ruby"

module TavernKit
  # Bounded cache for JS-style regex literals, e.g. "/h.llo/i".
  #
  # Used by both the SillyTavern and RisuAI lore engines.
  class JsRegexCache
    DEFAULT_MAX_SIZE = 512
    DEFAULT_MAX_LITERAL_BYTES = 2048
    DEFAULT_TIMEOUT_SECONDS = 0.1

    def initialize(max_size: DEFAULT_MAX_SIZE, literal_only: true, max_literal_bytes: DEFAULT_MAX_LITERAL_BYTES, timeout: DEFAULT_TIMEOUT_SECONDS)
      @cache = TavernKit::LRUCache.new(max_size: max_size)
      @literal_only = literal_only == true
      @max_literal_bytes = Integer(max_literal_bytes)
      @timeout = timeout.nil? ? nil : Float(timeout)
    end

    def fetch(value)
      v = value.to_s
      return nil unless v.start_with?("/")
      return nil if @max_literal_bytes.positive? && v.bytesize > @max_literal_bytes

      @cache.fetch(v) do
        re = ::JsRegexToRuby.try_convert(v, literal_only: @literal_only)
        return nil unless re.is_a?(Regexp)

        return re if @timeout.nil? || @timeout <= 0

        begin
          # Ruby 3.2+ supports per-regexp timeouts.
          Regexp.new(re.source, re.options, timeout: @timeout)
        rescue ArgumentError
          re
        end
      end
    rescue RegexpError
      nil
    end

    def clear = @cache.clear
    def size = @cache.size
  end
end
