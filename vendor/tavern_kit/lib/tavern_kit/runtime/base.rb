# frozen_string_literal: true

module TavernKit
  module Runtime
    # Base class for platform "runtime" state contracts.
    #
    # A Runtime is the application-owned state that must stay in sync with the
    # prompt-building pipeline (e.g., chat/message indices, app metadata, feature
    # toggles). It is intentionally separate from Prompt::Context, which is
    # per-build working memory.
    class Base
      attr_reader :type, :id

      def self.build(raw, **kwargs)
        new(normalize(raw, **kwargs), **kwargs)
      end

      def self.normalize(raw, **_kwargs)
        normalize_hash_keys(raw)
      end

      def self.normalize_hash_keys(raw)
        h = raw.is_a?(Hash) ? raw : {}

        h.each_with_object({}) do |(key, value), out|
          underscored = TavernKit::Utils.underscore(key)
          next if underscored.strip.empty?

          out[underscored.to_sym] = value
        end
      end
      private_class_method :normalize_hash_keys

      def initialize(data = {}, type: nil, id: nil, **_kwargs)
        @type = type&.to_sym
        @id = id&.to_s
        @data = data.is_a?(Hash) ? data : {}
      end

      def to_h
        @data.dup
      end

      def [](key)
        @data[key]
      end
    end
  end
end
