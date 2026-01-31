# frozen_string_literal: true

require "tiktoken_ruby"

module TavernKit
  # Token counting utility with a pluggable adapter interface.
  class TokenEstimator
    module Adapter
      class Base
        def estimate(text, model_hint: nil) = raise NotImplementedError
      end

      class Tiktoken < Base
        DEFAULT_ENCODING = "cl100k_base"

        def initialize(default_encoding: DEFAULT_ENCODING)
          @default = ::Tiktoken.get_encoding(default_encoding)
          @encodings = {}
        end

        def estimate(text, model_hint: nil)
          encoding_for(model_hint).encode(text.to_s).length
        end

        private

        def encoding_for(model_hint)
          return @default if model_hint.nil?

          key = model_hint.to_s
          return @default if key.empty?

          # Cache the encoding per model hint. This is a CPU-bound hot path when
          # trimming/budgeting repeatedly estimates token counts.
          @encodings[key] ||= (::Tiktoken.encoding_for_model(key) || @default)
        rescue StandardError
          @default
        end
      end
    end

    def self.default
      @default ||= new
    end

    def initialize(adapter: Adapter::Tiktoken.new)
      @adapter = adapter
    end

    def estimate(text, model_hint: nil)
      @adapter.estimate(text, model_hint: model_hint)
    end
  end
end
