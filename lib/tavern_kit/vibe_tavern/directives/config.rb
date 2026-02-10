# frozen_string_literal: true

require_relative "presets"

module TavernKit
  module VibeTavern
    module Directives
      DEFAULT_MODES = %i[json_schema json_object prompt_only].freeze

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
          def self.from_runtime(runtime, provider:, model: nil)
            base =
              TavernKit::VibeTavern::Directives::Presets.for(
                provider: provider,
                model: model,
              )

            raw = runtime&.[](:directives)
            raise ArgumentError, "runtime[:directives] must be a Hash" unless raw.nil? || raw.is_a?(Hash)

            merged =
              TavernKit::VibeTavern::Directives::Presets.merge(
                base,
                raw,
              )

            build_from_hash(merged)
          end

          def self.build_from_hash(raw)
            raise ArgumentError, "directives config must be a Hash" unless raw.is_a?(Hash)
            assert_symbol_keys!(raw)

            modes =
              Array(raw.fetch(:modes, DEFAULT_MODES))
                .map { |m| m.to_s.strip.downcase.tr("-", "_").to_sym }
                .select { |m| DEFAULT_MODES.include?(m) }
            modes = DEFAULT_MODES.dup if modes.empty?

            repair_retry_count = raw.fetch(:repair_retry_count, 1)
            repair_retry_count = integer_or_default(repair_retry_count, default: 1)
            repair_retry_count = 0 if repair_retry_count.negative?

            request_overrides = hash_or_empty(raw.fetch(:request_overrides, {}))
            structured_request_overrides = hash_or_empty(raw.fetch(:structured_request_overrides, {}))
            prompt_only_request_overrides = hash_or_empty(raw.fetch(:prompt_only_request_overrides, {}))

            assert_symbol_keys!(request_overrides)
            assert_symbol_keys!(structured_request_overrides)
            assert_symbol_keys!(prompt_only_request_overrides)

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

          def self.hash_or_empty(value)
            return {} if value.nil?
            raise ArgumentError, "config must be a Hash" unless value.is_a?(Hash)

            value
          end
          private_class_method :hash_or_empty

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

          def self.assert_symbol_keys!(hash)
            hash.each_key do |k|
              raise ArgumentError, "config keys must be Symbols (got #{k.class})" unless k.is_a?(Symbol)
            end
          end
          private_class_method :assert_symbol_keys!
        end
    end
  end
end
