# frozen_string_literal: true

require "json"

module TavernKit
  # Provider dialect conversions for Prompt::Message objects.
  #
  # Dialects convert the core, provider-agnostic Message model into request
  # payload shapes expected by specific LLM APIs (OpenAI/Anthropic/etc).
  module Dialects
    class << self
      def register(name, klass)
        @registry ||= {}
        @registry[name.to_sym] = klass
      end

      def convert(messages, dialect:, **opts)
        adapter = adapter_for(dialect)
        adapter.new.convert(messages, **opts)
      end

      def adapter_for(dialect)
        @registry ||= {}
        klass = @registry[dialect.to_sym]
        raise ArgumentError, "Unknown dialect: #{dialect.inspect}" unless klass

        klass
      end

      def registered
        (@registry || {}).dup
      end
    end

    class Base
      private

      def role_string(role)
        role.to_s
      end

      def message_metadata(message)
        meta = message.metadata
        return {} unless meta.is_a?(Hash)

        meta
      end

      def fetch_meta(message, key)
        meta = message_metadata(message)
        meta[key] || meta[key.to_s]
      end

      def compact_hash(hash)
        hash.reject { |_, v| v.nil? }
      end

      def safe_parse_json(value)
        return value unless value.is_a?(String)
        return value unless value.strip.start_with?("{", "[")

        JSON.parse(value)
      rescue JSON::ParserError
        value
      end
    end
  end
end
