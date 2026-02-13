# frozen_string_literal: true

module TavernKit
  module VibeTavern
    Capabilities =
      Data.define(
        :provider,
        :model,
        :supports_tool_calling,
        :supports_response_format_json_object,
        :supports_response_format_json_schema,
        :supports_streaming,
        :supports_parallel_tool_calls,
        :context_window_tokens,
        :reserved_response_tokens,
      ) do
        def self.resolve(provider:, model:, overrides: nil)
          provider_s = provider.to_s.strip
          raise ArgumentError, "provider is required" if provider_s.empty?

          model_s = model.to_s.strip
          raise ArgumentError, "model is required" if model_s.empty?

          provider_id = provider_s.downcase.tr("-", "_").to_sym

          # VibeTavern targets OpenAI-compatible APIs but providers/models vary
          # in real-world support. Keep unknown provider/model combinations
          # conservative by default.
          defaults = {
            supports_tool_calling: true,
            supports_response_format_json_object: true,
            supports_response_format_json_schema: false,
            supports_streaming: true,
            supports_parallel_tool_calls: false,
            context_window_tokens: nil,
            reserved_response_tokens: 0,
          }

          merged = defaults.merge(normalize_overrides(overrides))

          context_window_tokens =
            normalize_optional_positive_int(
              merged.fetch(:context_window_tokens, nil),
              name: "context_window_tokens",
            )
          reserved_response_tokens =
            normalize_non_negative_int(
              merged.fetch(:reserved_response_tokens, 0),
              name: "reserved_response_tokens",
            )

          if context_window_tokens && reserved_response_tokens > context_window_tokens
            raise ArgumentError,
                  "reserved_response_tokens (#{reserved_response_tokens}) exceeds context_window_tokens (#{context_window_tokens})"
          end

          new(
            provider: provider_id,
            model: model_s,
            **merged.merge(
              context_window_tokens: context_window_tokens,
              reserved_response_tokens: reserved_response_tokens,
            ),
          )
        end

        def self.normalize_overrides(value)
          return {} if value.nil?

          raise ArgumentError, "overrides must be a Hash" unless value.is_a?(Hash)

          value.each_key do |key|
            raise ArgumentError, "overrides keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
          end

          value.reject { |_k, v| v.nil? }.dup
        end
        private_class_method :normalize_overrides

        def self.normalize_optional_positive_int(value, name:)
          return nil if value.nil?

          int = Integer(value)
          raise ArgumentError, "#{name} must be positive (got #{value.inspect})" unless int.positive?

          int
        rescue ArgumentError, TypeError
          raise ArgumentError, "#{name} must be a positive Integer (got #{value.inspect})"
        end
        private_class_method :normalize_optional_positive_int

        def self.normalize_non_negative_int(value, name:)
          int = Integer(value)
          raise ArgumentError, "#{name} must be non-negative (got #{value.inspect})" if int.negative?

          int
        rescue ArgumentError, TypeError
          raise ArgumentError, "#{name} must be a non-negative Integer (got #{value.inspect})"
        end
        private_class_method :normalize_non_negative_int
      end
  end
end
