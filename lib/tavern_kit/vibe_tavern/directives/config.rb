# frozen_string_literal: true

require_relative "constants"
require_relative "presets"

module TavernKit
  module VibeTavern
    module Directives
      Config =
        Data.define(
          :modes,
          :repair_retry_count,
          :request_overrides,
          :structured_request_overrides,
          :prompt_only_request_overrides,
          :message_transforms,
          :response_transforms,
        ) do
          def self.from_context(context, provider:, model: nil)
            base =
              TavernKit::VibeTavern::Directives::Presets.for(
                provider: provider,
                model: model,
              )

            raw = context&.[](:directives)
            raise ArgumentError, "context[:directives] must be a Hash" unless raw.nil? || raw.is_a?(Hash)

            merged =
              TavernKit::VibeTavern::Directives::Presets.merge(
                base,
                raw,
              )

            build_from_hash(merged)
          end

          def self.build_from_hash(raw)
            raise ArgumentError, "directives config must be a Hash" unless raw.is_a?(Hash)
            TavernKit::Utils.assert_symbol_keys!(raw, path: "directives config")

            modes =
              Array(raw.fetch(:modes, DEFAULT_MODES))
                .map { |m| m.to_s.strip.downcase.tr("-", "_").to_sym }
                .select { |m| DEFAULT_MODES.include?(m) }
            modes = DEFAULT_MODES.dup if modes.empty?

            repair_retry_count = raw.fetch(:repair_retry_count, DEFAULT_REPAIR_RETRY_COUNT)
            repair_retry_count = integer_or_default(repair_retry_count, default: DEFAULT_REPAIR_RETRY_COUNT)
            repair_retry_count = 0 if repair_retry_count.negative?

            request_overrides = TavernKit::Utils.normalize_symbol_keyed_hash(raw.fetch(:request_overrides, {}), path: "directives.request_overrides")
            structured_request_overrides = TavernKit::Utils.normalize_symbol_keyed_hash(raw.fetch(:structured_request_overrides, {}), path: "directives.structured_request_overrides")
            prompt_only_request_overrides = TavernKit::Utils.normalize_symbol_keyed_hash(raw.fetch(:prompt_only_request_overrides, {}), path: "directives.prompt_only_request_overrides")

            message_transforms = normalize_string_array(raw.fetch(:message_transforms, nil))
            response_transforms = normalize_string_array(raw.fetch(:response_transforms, nil))

            new(
              modes: modes,
              repair_retry_count: repair_retry_count,
              request_overrides: request_overrides,
              structured_request_overrides: structured_request_overrides,
              prompt_only_request_overrides: prompt_only_request_overrides,
              message_transforms: message_transforms,
              response_transforms: response_transforms,
            )
          end

          def self.integer_or_default(value, default:)
            Integer(value)
          rescue ArgumentError, TypeError
            default
          end
          private_class_method :integer_or_default

          def self.normalize_string_array(value)
            Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
          end
          private_class_method :normalize_string_array
        end
    end
  end
end
