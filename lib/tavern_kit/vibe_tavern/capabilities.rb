# frozen_string_literal: true

module TavernKit
  module VibeTavern
    Capabilities =
      Data.define(
        :provider,
        :model,
        :supports_tools,
        :supports_response_format_json_object,
        :supports_response_format_json_schema,
        :supports_streaming,
        :supports_parallel_tool_calls,
      ) do
        def self.resolve(provider:, model:)
          provider_s = provider.to_s.strip
          raise ArgumentError, "provider is required" if provider_s.empty?

          model_s = model.to_s.strip
          raise ArgumentError, "model is required" if model_s.empty?

          provider_id = provider_s.downcase.tr("-", "_").to_sym

          # VibeTavern targets OpenAI-compatible APIs. If a provider/model does
          # not support a capability, prefer explicit, per-provider policy
          # in RunnerConfig/context rather than silent coercion.
          new(
            provider: provider_id,
            model: model_s,
            supports_tools: true,
            supports_response_format_json_object: true,
            supports_response_format_json_schema: true,
            supports_streaming: true,
            supports_parallel_tool_calls: true,
          )
        end
      end
  end
end
