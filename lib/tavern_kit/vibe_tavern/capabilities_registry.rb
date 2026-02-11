# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module CapabilitiesRegistry
      module_function

      PROVIDER_ALIASES = {
        open_router: :openrouter,
        volcanoengine: :volcano_engine,
        volcano: :volcano_engine,
      }.freeze

      @default_overrides = {}.freeze

      REGISTRY =
        {
          openai: {
            default: {
              supports_tools: true,
              supports_response_format_json_object: true,
              supports_response_format_json_schema: true,
              supports_streaming: true,
              supports_parallel_tool_calls: true,
            },
            models: [],
          },
          openrouter: {
            default: {
              supports_tools: true,
              supports_response_format_json_object: true,
              supports_response_format_json_schema: true,
              supports_streaming: true,
              supports_parallel_tool_calls: true,
            },
            models: [
              [
                /\Aanthropic\//,
                { supports_response_format_json_schema: false },
              ],
              [
                /\Aopenai\//,
                {
                  supports_response_format_json_object: false,
                  supports_response_format_json_schema: false,
                },
              ],
              [
                /\Aminimax\//,
                {
                  supports_response_format_json_object: false,
                  supports_response_format_json_schema: false,
                },
              ],
              [
                "minimax/minimax-m2-her",
                {
                  supports_tools: false,
                  supports_response_format_json_object: false,
                  supports_response_format_json_schema: false,
                },
              ],
            ],
          },
          volcano_engine: {
            default: {
              supports_parallel_tool_calls: true,
            },
            models: [],
          },
        }.freeze

      def default_overrides
        @default_overrides
      end

      def configure_default_overrides(**overrides)
        overrides.each_key do |key|
          raise ArgumentError, "default_overrides keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
        end

        @default_overrides = overrides.reject { |_k, v| v.nil? }.dup.freeze
      end

      def lookup(provider_id:, model:)
        provider = canonical_provider_id(provider_id)
        model_s = model.to_s

        out = default_overrides.dup

        entry = REGISTRY[provider]
        if entry.is_a?(Hash)
          defaults = entry.fetch(:default, nil)
          out.merge!(defaults) if defaults.is_a?(Hash)
        end

        Array(entry.is_a?(Hash) ? entry.fetch(:models, nil) : nil).each do |pattern, overrides|
          next unless overrides.is_a?(Hash)

          matches =
            case pattern
            when String
              model_s == pattern
            when Regexp
              pattern.match?(model_s)
            else
              false
            end

          next unless matches

          out.merge!(overrides)
        end

        out
      end

      def canonical_provider_id(value)
        raw = value.to_s.strip
        return nil if raw.empty?

        provider = raw.downcase.tr("-", "_").to_sym
        PROVIDER_ALIASES.fetch(provider, provider)
      end
      private_class_method :canonical_provider_id
    end
  end
end
