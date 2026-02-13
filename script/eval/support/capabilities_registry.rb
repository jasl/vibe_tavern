# frozen_string_literal: true

# Eval-only capability overrides.
#
# Runtime capabilities are owned by the app (DB-backed `LLMModel` columns). The
# eval harness still needs a small curated matrix of provider/model quirks.
module VibeTavernEval
  module CapabilitiesRegistry
    module_function

    PROVIDER_ALIASES = {
      open_router: :openrouter,
      volcanoengine: :volcano_engine,
      volcano: :volcano_engine,
    }.freeze

    REGISTRY =
      {
        openai: {
          default: {
            supports_tool_calling: true,
            supports_response_format_json_object: true,
            supports_response_format_json_schema: true,
            supports_streaming: true,
            supports_parallel_tool_calls: true,
          },
          models: [],
        },
        openrouter: {
          default: {
            supports_tool_calling: true,
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
                supports_tool_calling: false,
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

    def lookup(provider_id:, model:)
      provider = canonical_provider_id(provider_id)
      model_s = model.to_s

      out = {}

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
